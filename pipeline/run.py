"""
Orchestrator: run the full curation pipeline end-to-end.

Usage:
    python -m pipeline.run \
        --lichess pipeline/input/mock_lichess.csv \
        --famous pipeline/famous_positions.json \
        --themes pipeline/themes.yaml \
        --out pipeline/output/puzzles.sqlite \
        --version 0.1.0 \
        --per-theme 200
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from .stages.load import load_all
from .stages.themes import ThemeTaxonomy, apply_themes
from .stages.score import score_all
from .stages.filter_and_bucket import quality_filter, stratified_sample
from .stages.emit import emit, source_hash_of
from .stages.validate import validate, report as report_rejects


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--lichess", type=Path, required=True)
    p.add_argument("--famous", type=Path, required=True)
    p.add_argument("--themes", type=Path, default=Path("pipeline/themes.yaml"))
    p.add_argument("--out", type=Path, default=Path("pipeline/output/puzzles.sqlite"))
    p.add_argument("--version", type=str, default="0.1.0-dev")
    p.add_argument("--per-theme", type=int, default=200,
                   help="target puzzle count per theme after sampling")
    p.add_argument("--coverage-out", type=Path,
                   default=Path("pipeline/output/coverage.json"))
    args = p.parse_args()

    tax = ThemeTaxonomy(args.themes)
    if not tax.prereqs_dag_valid():
        print("ERROR: theme prereq graph has a cycle", file=sys.stderr)
        return 2

    # Pipeline order is tuned so the most expensive stages (python-chess
    # validation, scoring features) only touch the subset that survives
    # the cheap predicates. Without this, a full 5.88M-row run takes
    # ~100 min; with it, ~2 min.
    puzzles = load_all(args.lichess, args.famous)
    print(f"loaded {len(puzzles)} puzzles", file=sys.stderr)

    # Cheap stage 1: theme map. Drops rows with no recognized themes.
    puzzles = apply_themes(puzzles, tax)
    print(f"after theme map: {len(puzzles)}", file=sys.stderr)

    # Cheap stage 2: quality filter on CSV-only fields.
    puzzles = quality_filter(puzzles, per_theme_target=args.per_theme)
    print(f"after quality filter: {len(puzzles)}", file=sys.stderr)

    # Expensive stages only on the survivors.
    puzzles, rejects = validate(puzzles)
    report_rejects(rejects)
    print(f"after validation: {len(puzzles)}", file=sys.stderr)

    puzzles = score_all(puzzles)

    puzzles = stratified_sample(puzzles, per_theme_target=args.per_theme)
    print(f"after stratified sample: {len(puzzles)}", file=sys.stderr)

    if not puzzles:
        print("ERROR: no puzzles survived pipeline", file=sys.stderr)
        return 3

    emit(
        puzzles, tax, args.out,
        version=args.version,
        source_hash=source_hash_of(args.lichess, args.famous, args.themes),
    )
    print(f"wrote {args.out}", file=sys.stderr)

    # Coverage report.
    theme_counts: Counter = Counter()
    rating_counts: Counter = Counter()
    for pz in puzzles:
        for t in pz.themes:
            theme_counts[t] += 1
        rating_counts[100 * (pz.rating // 100)] += 1
    interest_hist = [0] * 20
    for pz in puzzles:
        interest_hist[min(int(pz.interest * 20), 19)] += 1
    args.coverage_out.parent.mkdir(parents=True, exist_ok=True)
    args.coverage_out.write_text(json.dumps({
        "n_puzzles": len(puzzles),
        "themes": dict(theme_counts),
        "rating_buckets": {str(k): v for k, v in sorted(rating_counts.items())},
        "interest_histogram": interest_hist,
    }, indent=2))
    print(f"wrote {args.coverage_out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
