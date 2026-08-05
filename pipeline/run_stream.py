"""
Streaming curation pipeline.

Unlike `run.py`, this processes the Lichess CSV row-by-row and writes
chunks to `puzzles.sqlite` as it goes, so memory stays flat regardless of
input size. The output DB is only complete after finalize() runs: until
then `corpus_meta` and `daily_index` are empty, theme floors are
placeholders and the `interest` column holds unnormalized partial sums —
a crash mid-run leaves a half-baked file that must be rebuilt. At app
ship-time, bumping the `assetVersion` string in
`app/lib/data/puzzle_db.dart` triggers a fresh copy on the next launch
via the `puzzles.sqlite.version` sidecar. (The app does NOT sha256 the
file on every launch; that was an Android ANR.)

Usage:
    python -m pipeline.run_stream \
        --lichess pipeline/input/lichess_full.csv \
        --famous pipeline/famous_positions.json \
        --themes pipeline/themes.yaml \
        --out pipeline/output/puzzles.sqlite \
        --per-theme 300 \
        --chunk-size 500

Writes progress to stderr as each chunk commits. Exits when every theme
has hit its quota or the CSV is exhausted.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

import chess

from .stages.emit import SCHEMA, DAILY_TOP_QUANTILE, source_hash_of, \
    percentile, built_at_iso
from .stages.load import Puzzle, ROW_PARSE_ERRORS, load_famous_json
from .stages.score import compute_features, WEIGHTS
from .stages.themes import ThemeTaxonomy


def cheap_csv_predicate(
    row: dict, rare_themes: set[str], tax: ThemeTaxonomy
) -> list[str] | None:
    """Return the row's canonical themes iff it is worth the expensive
    stages, else None.

    Rare themes get a relaxed filter (RD only). Common themes need the
    standard popularity / plays / RD bar. Only accepts rows that also have
    at least one theme we recognize. Returning the canonical list (instead
    of a bool) saves the caller recomputing it for every surviving row.
    """
    tags = row["Themes"].split()
    canonical = tax.canonical(tags)
    if not canonical:
        return None
    primary = canonical[0]
    rd = int(row["RatingDeviation"])
    if primary in rare_themes:
        return canonical if rd <= 120 else None
    if rd > 90:
        return None
    if int(row["NbPlays"]) < 1000:
        return None
    if int(row["Popularity"]) < 80:
        return None
    return canonical


def validate_solution(fen: str, setup_uci: str, moves_uci: list[str]) -> bool:
    try:
        b = chess.Board(fen)
    except ValueError:
        return False
    if setup_uci:
        try:
            mv = chess.Move.from_uci(setup_uci)
        except ValueError:
            return False
        if mv not in b.legal_moves:
            return False
        b.push(mv)
    for uci in moves_uci:
        try:
            mv = chess.Move.from_uci(uci)
        except ValueError:
            return False
        if mv not in b.legal_moves:
            return False
        b.push(mv)
    return True


def row_to_puzzle(row: dict, canonical: list[str]) -> Puzzle | None:
    moves = row["Moves"].split()
    if len(moves) < 2:
        return None
    setup = moves[0]
    rest = moves[1:]
    try:
        board = chess.Board(row["FEN"])
    except ValueError:
        return None
    try:
        mv = chess.Move.from_uci(setup)
    except ValueError:
        return None
    if mv not in board.legal_moves:
        return None
    board.push(mv)
    return Puzzle(
        id=row["PuzzleId"],
        fen=row["FEN"],
        setup_move=setup,
        side_to_move="w" if board.turn == chess.WHITE else "b",
        moves_uci=rest,
        themes=canonical,
        lichess_themes=row["Themes"].split(),
        rating=int(row["Rating"]),
        rating_dev=int(row["RatingDeviation"]),
        popularity=int(row["Popularity"]),
        nb_plays=int(row["NbPlays"]),
        origin_kind="lichess",
        origin_label=None,
        explanation=None,
    )


def raw_fixed_part(p: Puzzle, theme_frequency: dict[str, float]) -> float:
    """The part of the interest score that needs no corpus-wide statistics.

    Four of the ten features (popularity, plays, rating deviation, theme
    rarity) are z-scored against the whole corpus, which a streaming pass
    cannot know yet. This returns the remaining six terms; the `interest`
    column holds it until [normalize_interest] completes the score.

    Approximating the z-scores with fixed divisors — the previous approach —
    compressed interest into a 0.12-wide band, which left the `interest**2`
    weighting the app relies on with almost no signal.
    """
    feat = compute_features(p, theme_frequency)
    return (
        WEIGHTS["quiet_key"] * feat["quiet_key"]
        + WEIGHTS["sacrifice"] * feat["sacrifice"]
        + WEIGHTS["counter_intuitive"] * feat["counter_intuitive"]
        + WEIGHTS["economy"] * feat["economy"]
        + WEIGHTS["mate_bonus"] * feat["mate_bonus"]
        + WEIGHTS["underpromo_bonus"] * feat["underpromo_bonus"]
    )


def _mean_std(values: list[float]) -> tuple[float, float]:
    mean = sum(values) / len(values)
    var = sum((v - mean) ** 2 for v in values) / max(len(values) - 1, 1)
    return mean, (math.sqrt(var) or 1.0)


def _median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def normalize_interest(conn, theme_frequency: dict[str, float]) -> None:
    """Finish the interest score once the whole kept corpus is known.

    Mirrors `score.score_all`: z-normalize the four corpus-wide features, add
    the stored partial score, then map through a median/MAD sigmoid. This runs
    over the KEPT rows (order 10^5), not the 6M-row input, so it stays within
    a streaming budget while producing the statistic `run.py` produces.
    """
    rows = list(conn.execute(
        "SELECT p.id, p.popularity, p.nb_plays, p.rating_dev, p.interest, "
        "(SELECT theme_id FROM puzzle_themes WHERE puzzle_id = p.id "
        " ORDER BY position LIMIT 1) AS primary_theme "
        "FROM puzzles p"))
    if not rows:
        return

    popularity = [float(r[1]) for r in rows]
    log_plays = [math.log1p(r[2]) for r in rows]
    rating_dev = [float(r[3]) for r in rows]
    rarity = [
        1.0 / max(theme_frequency.get(r[5] or "", 1e-6), 1e-6) for r in rows
    ]

    pop_m, pop_s = _mean_std(popularity)
    play_m, play_s = _mean_std(log_plays)
    rd_m, rd_s = _mean_std(rating_dev)
    rar_m, rar_s = _mean_std(rarity)

    raws = [
        WEIGHTS["popularity"] * (popularity[i] - pop_m) / pop_s
        + WEIGHTS["log_plays"] * (log_plays[i] - play_m) / play_s
        + WEIGHTS["rating_dev"] * (rating_dev[i] - rd_m) / rd_s
        + WEIGHTS["theme_rarity"] * (rarity[i] - rar_m) / rar_s
        + float(rows[i][4])
        for i in range(len(rows))
    ]

    med = _median(raws)
    mad = _median([abs(v - med) for v in raws]) or 1.0
    scale = 1.4826 * mad

    updates = []
    for i, row in enumerate(rows):
        # Clamp the exponent: |z| grows with sqrt(n), and at corpus scale a
        # single extreme outlier is enough to overflow math.exp.
        z = max(-60.0, min(60.0, (raws[i] - med) / scale))
        updates.append((1.0 / (1.0 + math.exp(-z)), row[0]))
    conn.executemany("UPDATE puzzles SET interest = ? WHERE id = ?", updates)


def init_db(path: Path, tax: ThemeTaxonomy) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(str(path))
    conn.executescript(SCHEMA)
    # Seed themes with placeholder floor/ceiling; finalized on close().
    rows = [
        (t["id"], t["display"], t["description"], t["importance"], 800, 2200)
        for t in tax.themes
    ]
    conn.executemany("INSERT INTO themes VALUES (?,?,?,?,?,?)", rows)
    # Seed prereqs.
    prereqs = [
        (t["id"], pr) for t in tax.themes for pr in t.get("prereqs", [])
    ]
    conn.executemany("INSERT INTO theme_prereqs VALUES (?,?)", prereqs)
    conn.commit()
    return conn


def flush_chunk(
    conn: sqlite3.Connection,
    chunk: list[Puzzle],
    theme_frequency: dict[str, float],
    tax: ThemeTaxonomy,
) -> None:
    puzzle_rows = []
    theme_rows = []
    for p in chunk:
        # Partial score only; normalize_interest() completes it in finalize().
        interest = raw_fixed_part(p, theme_frequency)
        puzzle_rows.append(
            (p.id, p.fen, p.setup_move, p.side_to_move,
             " ".join(p.moves_uci),
             p.rating, p.rating_dev, p.popularity, p.nb_plays,
             interest, p.origin_kind, p.origin_label, p.explanation)
        )
        for i, t in enumerate(p.themes):
            if t in tax.by_id:
                theme_rows.append((p.id, t, i))
    conn.executemany(
        "INSERT OR IGNORE INTO puzzles VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        puzzle_rows,
    )
    conn.executemany(
        "INSERT OR IGNORE INTO puzzle_themes VALUES (?,?,?)", theme_rows
    )
    conn.commit()


def finalize(
    conn: sqlite3.Connection,
    tax: ThemeTaxonomy,
    version: str,
    source_hash: str,
    theme_frequency: dict[str, float] | None = None,
) -> int:
    # Turn the stored partial scores into real interest values. Must run
    # before daily_index, which ranks on interest.
    if theme_frequency is not None:
        normalize_interest(conn, theme_frequency)

    # Compute per-theme floor/ceiling ratings from observed puzzles.
    by_theme_ratings: dict[str, list[int]] = {}
    for row in conn.execute(
            "SELECT p.rating, pt.theme_id FROM puzzles p "
            "JOIN puzzle_themes pt ON pt.puzzle_id = p.id"):
        r, t = row
        by_theme_ratings.setdefault(t, []).append(r)
    for t, ratings in by_theme_ratings.items():
        floor = percentile(ratings, 0.10)
        ceiling = percentile(ratings, 0.90)
        conn.execute(
            "UPDATE themes SET floor_rating=?, ceiling_rating=? WHERE id=?",
            (floor, ceiling, t),
        )

    # Daily index — same depth policy as emit.py, so both entry points
    # build the same daily pool for the same corpus size.
    conn.execute("DELETE FROM daily_index")
    n_puzzles = conn.execute("SELECT COUNT(*) FROM puzzles").fetchone()[0]
    n_daily = max(30, int(n_puzzles * DAILY_TOP_QUANTILE))
    rows = list(conn.execute(
        # `id` breaks interest ties; without it equal-interest puzzles order
        # by physical row position and the daily index is not reproducible.
        "SELECT id FROM puzzles ORDER BY interest DESC, id LIMIT ?",
        (n_daily,)))
    for i, (pid,) in enumerate(rows):
        conn.execute("INSERT INTO daily_index VALUES (?,?)", (i, pid))

    # Meta.
    n_themes = len(tax.themes)
    conn.execute("DELETE FROM corpus_meta")
    conn.execute(
        "INSERT INTO corpus_meta VALUES (?,?,?,?,?)",
        (version,
         built_at_iso(),
         source_hash,
         n_puzzles, n_themes),
    )
    conn.commit()
    return n_puzzles


def stream(
    lichess_csv: Path,
    famous_json: Path | None,
    tax: ThemeTaxonomy,
    out_path: Path,
    per_theme: int,
    chunk_size: int,
    coverage_path: Path | None,
    version: str,
    themes_path: Path | None = None,
) -> int:
    # Load famous positions first — they're few and should always land.
    famous: list[Puzzle] = []
    if famous_json and famous_json.exists():
        famous = list(load_famous_json(famous_json))
        # Auto-tag with 'famous' pseudo-theme if declared.
        if "famous" in tax.by_id:
            for p in famous:
                if "famous" not in p.themes:
                    p.themes = list(p.themes) + ["famous"]

    # First pass over the CSV to compute rare-theme set (cheap — just
    # iterate primary themes of every row). Malformed rows are skipped here
    # and counted in the main pass; a truncated download must not crash a
    # multi-hour build.
    print("[1/2] scanning theme frequencies...", file=sys.stderr)
    theme_counter: Counter = Counter()
    with lichess_csv.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            try:
                canonical = tax.canonical(row["Themes"].split())
            except ROW_PARSE_ERRORS:
                continue
            if canonical:
                theme_counter[canonical[0]] += 1
    rare_cutoff = 3 * per_theme
    rare_themes = {t for t, n in theme_counter.items() if n < rare_cutoff}
    theme_frequency = {
        t: n / max(sum(theme_counter.values()), 1)
        for t, n in theme_counter.items()
    }
    print(
        f"[1/2] rare themes (< {rare_cutoff} raw): "
        f"{sorted(rare_themes) if rare_themes else 'none'}",
        file=sys.stderr,
    )

    conn = init_db(out_path, tax)
    per_theme_count: dict[str, int] = defaultdict(int)
    # Ids already inserted. INSERT OR IGNORE would swallow a duplicate
    # silently AFTER kept/per_theme_count were incremented, overstating
    # coverage.json and the quota accounting.
    seen_ids: set[str] = set()

    # Emit famous positions first.
    flush_chunk(conn, famous, theme_frequency, tax)
    for f in famous:
        seen_ids.add(f.id)
        for t in f.themes:
            per_theme_count[t] += 1
    print(f"[2/2] wrote {len(famous)} famous positions", file=sys.stderr)

    def all_quotas_met() -> bool:
        # 'famous' is exempt: it fills from famous_positions.json (3 rows),
        # never from the CSV, so requiring it would keep the scan running
        # to the last row even with every real theme full.
        return all(
            per_theme_count[t["id"]] >= per_theme
            for t in tax.themes
            if t["id"] != "famous" and theme_counter.get(t["id"], 0) > 0
        )

    # Streaming pass.
    chunk: list[Puzzle] = []
    kept = 0
    seen_rows = 0
    malformed = 0
    with lichess_csv.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            seen_rows += 1
            if seen_rows % 100000 == 0:
                print(
                    f"[2/2] scanned {seen_rows}, kept {kept}, "
                    f"themes_full={sum(1 for t in tax.themes if per_theme_count[t['id']] >= per_theme)}",
                    file=sys.stderr,
                )
            try:
                canonical = cheap_csv_predicate(row, rare_themes, tax)
                if canonical is None:
                    continue
                # Keep the row only if it still helps some carried theme —
                # counters credit every theme a puzzle carries (the backfill
                # pass fills by any appearance too), so the gate must look
                # at all of them, not just the primary.
                if all(per_theme_count[t] >= per_theme for t in canonical):
                    continue
                if row["PuzzleId"] in seen_ids:
                    continue
                p = row_to_puzzle(row, canonical)
            except ROW_PARSE_ERRORS:
                malformed += 1
                continue
            if p is None:
                continue
            if not validate_solution(p.fen, p.setup_move, p.moves_uci):
                continue
            chunk.append(p)
            seen_ids.add(p.id)
            for t in p.themes:
                per_theme_count[t] += 1
            kept += 1
            if len(chunk) >= chunk_size:
                flush_chunk(conn, chunk, theme_frequency, tax)
                print(
                    f"[2/2] +{len(chunk)} committed (total {kept})",
                    file=sys.stderr,
                )
                chunk = []
            # Early exit: all CSV-fillable themes met quota.
            if all_quotas_met():
                print("[2/2] all themes full, stopping early", file=sys.stderr)
                break
    if malformed:
        print(
            f"[2/2] WARNING: skipped {malformed} malformed rows",
            file=sys.stderr,
        )

    if chunk:
        flush_chunk(conn, chunk, theme_frequency, tax)
        print(
            f"[2/2] +{len(chunk)} committed (total {kept})", file=sys.stderr
        )

    # Backfill pass: for any theme still under quota, re-scan the CSV
    # without the popularity/plays/RD filter. A row counts as backfill
    # material for theme T if T appears ANYWHERE in its canonical list —
    # not just as primary. Many niche themes (zugzwang, pawnEndgame) are
    # secondary on most puzzles that carry them.
    under = {
        t["id"] for t in tax.themes
        if per_theme_count[t["id"]] < per_theme and t["id"] != "famous"
    }
    if under:
        print(
            f"[3/3] backfill needed for {sorted(under)}, re-scanning",
            file=sys.stderr,
        )
        with lichess_csv.open(encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            chunk = []
            for row in reader:
                try:
                    pid = row["PuzzleId"]
                    if pid in seen_ids:
                        continue
                    tags = row["Themes"].split()
                    canonical = tax.canonical(tags)
                    if not canonical:
                        continue
                    # Include if ANY of the puzzle's themes is currently
                    # below quota.
                    if not any(t in under for t in canonical):
                        continue
                    p = row_to_puzzle(row, canonical)
                except ROW_PARSE_ERRORS:
                    continue
                if p is None:
                    continue
                if not validate_solution(p.fen, p.setup_move, p.moves_uci):
                    continue
                chunk.append(p)
                seen_ids.add(pid)
                for t in p.themes:
                    per_theme_count[t] += 1
                kept += 1
                # Shrink `under` as themes meet quota.
                under = {
                    u for u in under if per_theme_count[u] < per_theme
                }
                if len(chunk) >= chunk_size:
                    flush_chunk(conn, chunk, theme_frequency, tax)
                    print(
                        f"[3/3] +{len(chunk)} backfill (total {kept}, "
                        f"still under: {len(under)})",
                        file=sys.stderr,
                    )
                    chunk = []
                if not under:
                    break
            if chunk:
                flush_chunk(conn, chunk, theme_frequency, tax)
                print(
                    f"[3/3] +{len(chunk)} backfill (total {kept})",
                    file=sys.stderr,
                )

    # Finalize. The hash covers every input that shaped the corpus —
    # including the taxonomy, which changes bucketing and theme mapping.
    hash_inputs = [lichess_csv]
    if famous_json is not None and famous_json.exists():
        hash_inputs.append(famous_json)
    if themes_path is not None:
        hash_inputs.append(themes_path)
    source_hash = source_hash_of(*hash_inputs)
    n = finalize(conn, tax, version, source_hash, theme_frequency)
    conn.close()

    if coverage_path is not None:
        coverage_path.parent.mkdir(parents=True, exist_ok=True)
        coverage_path.write_text(json.dumps({
            "n_puzzles": n,
            "themes": dict(per_theme_count),
        }, indent=2))

    return n


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--lichess", type=Path, required=True)
    p.add_argument("--famous", type=Path, required=True)
    p.add_argument("--themes", type=Path, default=Path("pipeline/themes.yaml"))
    p.add_argument("--out", type=Path, default=Path("pipeline/output/puzzles.sqlite"))
    p.add_argument("--version", type=str, default="0.1.0-dev")
    p.add_argument("--per-theme", type=int, default=300)
    p.add_argument("--chunk-size", type=int, default=500)
    p.add_argument("--coverage-out", type=Path,
                   default=Path("pipeline/output/coverage.json"))
    args = p.parse_args()

    tax = ThemeTaxonomy(args.themes)
    if not tax.prereqs_dag_valid():
        print("ERROR: theme prereq graph has a cycle", file=sys.stderr)
        return 2

    n = stream(
        args.lichess,
        args.famous,
        tax,
        args.out,
        args.per_theme,
        args.chunk_size,
        args.coverage_out,
        args.version,
        themes_path=args.themes,
    )
    print(f"done — {n} puzzles in {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
