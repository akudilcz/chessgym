"""
Stage 5–6: quality filter + stratified sampling.

Per design/pipeline.md:
  - Drop puzzles below quality thresholds (Lichess tier only).
  - Stratified sample across (theme × rating_bucket) to guarantee coverage.
"""
from __future__ import annotations

from collections import defaultdict

from .load import Puzzle


def quality_filter(
    puzzles: list[Puzzle],
    per_theme_target: int,
) -> list[Puzzle]:
    """
    Strict filter for common themes, relaxed for rare ones.

    Common themes (≥ 3 × target raw puzzles): popularity ≥ 80, plays ≥ 1000,
    RD ≤ 90.
    Rare themes (< 3 × target): RD ≤ 120 only — we'd rather have slightly
    noisier puzzles than an empty category.

    Per-theme check uses the puzzle's PRIMARY theme (position 0).
    """
    # First pass: count raw-theme frequency across the input.
    by_theme: dict[str, int] = {}
    for p in puzzles:
        if p.themes:
            by_theme[p.themes[0]] = by_theme.get(p.themes[0], 0) + 1
    rare_cutoff = 3 * per_theme_target
    rare_themes = {t for t, n in by_theme.items() if n < rare_cutoff}

    kept: list[Puzzle] = []
    for p in puzzles:
        if p.origin_kind != "lichess":
            kept.append(p)
            continue
        if not p.themes:
            continue
        primary = p.themes[0]
        if primary in rare_themes:
            # Relaxed: only reject very-noisy ratings.
            if p.rating_dev > 120:
                continue
        else:
            if p.rating_dev > 90:
                continue
            if p.nb_plays < 1000:
                continue
            if p.popularity < 80:
                continue
        kept.append(p)
    return kept


def rating_bucket(rating: int) -> int:
    """100-wide buckets anchored at 600. Values <600 clamp to 600; ≥2400 to 2300."""
    b = max(600, min(rating, 2399))
    return (b // 100) * 100


def stratified_sample(
    puzzles: list[Puzzle],
    per_theme_target: int,
    per_cell_cap: int | None = None,
) -> list[Puzzle]:
    """
    For each theme, keep up to per_theme_target puzzles. Within a theme, spread
    across rating buckets (most-covered theme wins tiebreaks via highest interest).
    Deterministic given (id, interest).

    Non-Lichess puzzles (famous positions, studies) bypass sampling entirely:
    they are few, hand-curated, and must always land — matching both
    quality_filter above and the streaming entry point's guarantee.
    """
    chosen_ids: set[str] = set()
    chosen: list[Puzzle] = []
    for p in puzzles:
        if p.origin_kind != "lichess" and p.id not in chosen_ids:
            chosen.append(p)
            chosen_ids.add(p.id)

    # Group by primary theme.
    by_theme: dict[str, list[Puzzle]] = defaultdict(list)
    for p in puzzles:
        if p.origin_kind != "lichess" or not p.themes:
            continue
        by_theme[p.themes[0]].append(p)
    # Running count of picks per (theme, rating bucket). Recomputing this by
    # scanning `chosen` inside the pick loop makes the stage quadratic: at the
    # README's recommended --per-theme 10000 across 26 themes that is 260k
    # picks each rescanning a list of the same order, which measures in tens
    # of minutes for a value we can simply maintain.
    per_cell_counts: dict[tuple[str, int], int] = defaultdict(int)

    for theme, items in by_theme.items():
        # Bucket by rating.
        cells: dict[int, list[Puzzle]] = defaultdict(list)
        for p in items:
            cells[rating_bucket(p.rating)].append(p)
        # Sort each cell by (interest desc, id) for determinism.
        for cell in cells.values():
            cell.sort(key=lambda x: (-x.interest, x.id))

        # Round-robin pick across cells until target reached or sources exhausted.
        quota = per_theme_target
        cap = per_cell_cap if per_cell_cap is not None else per_theme_target
        picks = 0
        while picks < quota:
            progressed = False
            for bucket, cell in sorted(cells.items()):
                if not cell:
                    continue
                if per_cell_counts[(theme, bucket)] >= cap:
                    continue
                p = cell.pop(0)
                # Consuming a cell entry IS progress, even when the entry
                # turns out to be a duplicate — otherwise a duplicate at the
                # head of the only remaining cell would end the round-robin
                # with fresh puzzles still queued behind it.
                progressed = True
                if p.id in chosen_ids:
                    continue
                chosen.append(p)
                chosen_ids.add(p.id)
                per_cell_counts[(theme, bucket)] += 1
                picks += 1
                if picks >= quota:
                    break
            if not progressed:
                break

    return chosen
