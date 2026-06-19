"""
Stage 8: emit puzzles.sqlite per design/schema.md.
"""
from __future__ import annotations

import hashlib
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from .load import Puzzle
from .themes import ThemeTaxonomy


def built_at_iso() -> str:
    """Build timestamp for `corpus_meta`, overridable via SOURCE_DATE_EPOCH.

    A wall-clock timestamp is the one field that stops two runs over identical
    inputs producing byte-identical files. Honouring the reproducible-builds
    convention lets a release pin it and diff the artifact.
    """
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        return datetime.fromtimestamp(
            int(epoch), timezone.utc).isoformat(timespec="seconds")
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


SCHEMA = """
CREATE TABLE puzzles (
  id            TEXT PRIMARY KEY,
  fen           TEXT NOT NULL,
  setup_move    TEXT NOT NULL,
  side_to_move  TEXT NOT NULL CHECK(side_to_move IN ('w','b')),
  moves_uci     TEXT NOT NULL,
  rating        INTEGER NOT NULL,
  rating_dev    INTEGER NOT NULL,
  popularity    INTEGER NOT NULL,
  nb_plays      INTEGER NOT NULL,
  interest      REAL NOT NULL,
  origin_kind   TEXT NOT NULL CHECK(origin_kind IN ('lichess','study','famous')),
  origin_label  TEXT,
  explanation   TEXT
);
-- No index on rating or interest. Every app query reaches puzzles through
-- puzzle_themes and then GROUP BYs, so SQLite sorts into a temp B-tree and
-- ignores such an index even when it exists (verified with EXPLAIN QUERY
-- PLAN on the full corpus). They cost 5.5 MB in a file that ships inside
-- the app, which is a real download for every user, and buy nothing.

CREATE TABLE puzzle_themes (
  puzzle_id TEXT NOT NULL REFERENCES puzzles(id),
  theme_id  TEXT NOT NULL REFERENCES themes(id),
  position  INTEGER NOT NULL,
  PRIMARY KEY (puzzle_id, theme_id)
);
CREATE INDEX idx_puzzle_themes_theme ON puzzle_themes(theme_id);

CREATE TABLE themes (
  id             TEXT PRIMARY KEY,
  display_name   TEXT NOT NULL,
  description    TEXT NOT NULL,
  importance     REAL NOT NULL,
  floor_rating   INTEGER NOT NULL,
  ceiling_rating INTEGER NOT NULL
);

CREATE TABLE theme_prereqs (
  theme_id   TEXT NOT NULL REFERENCES themes(id),
  prereq_id  TEXT NOT NULL REFERENCES themes(id),
  PRIMARY KEY (theme_id, prereq_id)
);

CREATE TABLE daily_index (
  slot       INTEGER PRIMARY KEY,
  puzzle_id  TEXT NOT NULL REFERENCES puzzles(id)
);

CREATE TABLE corpus_meta (
  version      TEXT NOT NULL,
  built_at     TEXT NOT NULL,
  source_hash  TEXT NOT NULL,
  n_puzzles    INTEGER NOT NULL,
  n_themes     INTEGER NOT NULL
);
"""


def percentile(xs: list[int], p: float) -> int:
    if not xs:
        return 0
    s = sorted(xs)
    k = int((len(s) - 1) * p)
    return s[k]


def emit(
    puzzles: list[Puzzle],
    tax: ThemeTaxonomy,
    out_path: Path,
    version: str,
    source_hash: str,
    daily_top_quantile: float = 0.05,
) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.executescript(SCHEMA)

        # Per-theme floor/ceiling computed from the kept corpus.
        by_theme_ratings: dict[str, list[int]] = {}
        for p in puzzles:
            for t in p.themes:
                by_theme_ratings.setdefault(t, []).append(p.rating)

        # themes.
        theme_rows = []
        for t in tax.themes:
            ratings = by_theme_ratings.get(t["id"], [])
            floor = percentile(ratings, 0.10) if ratings else 800
            ceiling = percentile(ratings, 0.90) if ratings else 2200
            theme_rows.append((
                t["id"], t["display"], t["description"],
                t["importance"], floor, ceiling,
            ))
        conn.executemany(
            "INSERT INTO themes VALUES (?,?,?,?,?,?)", theme_rows,
        )

        # theme_prereqs.
        prereq_rows = []
        for t in tax.themes:
            for pr in t.get("prereqs", []):
                prereq_rows.append((t["id"], pr))
        conn.executemany(
            "INSERT INTO theme_prereqs VALUES (?,?)", prereq_rows,
        )

        # puzzles.
        puzzle_rows = []
        puzzle_theme_rows = []
        for p in puzzles:
            puzzle_rows.append((
                p.id, p.fen, p.setup_move, p.side_to_move,
                " ".join(p.moves_uci),
                p.rating, p.rating_dev, p.popularity, p.nb_plays,
                p.interest, p.origin_kind, p.origin_label, p.explanation,
            ))
            for i, t in enumerate(p.themes):
                if t not in tax.by_id:
                    continue
                puzzle_theme_rows.append((p.id, t, i))
        conn.executemany(
            "INSERT INTO puzzles VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            puzzle_rows,
        )
        conn.executemany(
            "INSERT OR IGNORE INTO puzzle_themes VALUES (?,?,?)",
            puzzle_theme_rows,
        )

        # daily_index: top-quantile puzzles by interest, stable-sorted by id.
        top = sorted(puzzles, key=lambda p: (-p.interest, p.id))
        n_daily = max(30, int(len(puzzles) * daily_top_quantile))
        daily = top[:n_daily]
        conn.executemany(
            "INSERT INTO daily_index VALUES (?,?)",
            [(i, p.id) for i, p in enumerate(daily)],
        )

        # corpus_meta.
        conn.execute(
            "INSERT INTO corpus_meta VALUES (?,?,?,?,?)",
            (version,
             built_at_iso(),
             source_hash,
             len(puzzles),
             len(tax.themes)),
        )
        conn.commit()
    finally:
        conn.close()


def source_hash_of(*paths: Path) -> str:
    h = hashlib.sha256()
    for p in paths:
        if p and p.exists():
            h.update(p.read_bytes())
    return h.hexdigest()[:16]
