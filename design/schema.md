# Schema

Single source of truth for the data shapes consumed by the app. The build-time pipeline produces `puzzles.sqlite` to this schema; the runtime app reads it and maintains a separate `player.sqlite` for mutable state.

## Two databases, one shipped, one local

- **`puzzles.sqlite`** — ships as a Flutter asset. Read-only at runtime. Rebuilt per release by `pipeline/`.
- **`player.sqlite`** — created on first launch in the app sandbox. Holds all mutable state.

Keeping them separate means app updates can ship a new puzzle database without touching player state, and a player reset can wipe `player.sqlite` without side effects.

## `puzzles.sqlite`

### Table `puzzles`

```sql
CREATE TABLE puzzles (
  id            TEXT PRIMARY KEY,            -- Lichess id or synthetic for composed
  fen           TEXT NOT NULL,               -- position BEFORE setup move
  setup_move    TEXT NOT NULL,               -- UCI, applied to fen to get displayed pos
  side_to_move  TEXT NOT NULL CHECK(side_to_move IN ('w','b')),
  moves_uci     TEXT NOT NULL,               -- space-separated UCI, solver+opponent alternating
  rating        INTEGER NOT NULL,
  rating_dev    INTEGER NOT NULL,
  popularity    INTEGER NOT NULL,            -- -100..100
  nb_plays      INTEGER NOT NULL,
  interest      REAL NOT NULL,               -- [0,1]
  origin_kind   TEXT NOT NULL CHECK(origin_kind IN ('lichess','study','famous')),
  origin_label  TEXT,                        -- "Kubbel 1922" etc, nullable
  explanation   TEXT                         -- author prose, nullable
);
CREATE INDEX idx_puzzles_rating ON puzzles(rating);
CREATE INDEX idx_puzzles_interest ON puzzles(interest DESC);
```

### Table `puzzle_themes`

Many-to-many. Order by `position` so primary theme is first.

```sql
CREATE TABLE puzzle_themes (
  puzzle_id TEXT NOT NULL REFERENCES puzzles(id),
  theme_id  TEXT NOT NULL REFERENCES themes(id),
  position  INTEGER NOT NULL,
  PRIMARY KEY (puzzle_id, theme_id)
);
CREATE INDEX idx_puzzle_themes_theme ON puzzle_themes(theme_id);
```

### Table `themes`

```sql
CREATE TABLE themes (
  id             TEXT PRIMARY KEY,           -- e.g. "backRankMate"
  display_name   TEXT NOT NULL,
  description    TEXT NOT NULL,
  importance     REAL NOT NULL,              -- [0,1], drives node size
  floor_rating   INTEGER NOT NULL,
  ceiling_rating INTEGER NOT NULL
);
```

### Table `theme_prereqs`

```sql
CREATE TABLE theme_prereqs (
  theme_id     TEXT NOT NULL REFERENCES themes(id),
  prereq_id    TEXT NOT NULL REFERENCES themes(id),
  PRIMARY KEY (theme_id, prereq_id)
);
```

### Table `daily_index`

Deterministic date-to-puzzle mapping for the daily puzzle feature.

```sql
CREATE TABLE daily_index (
  slot       INTEGER PRIMARY KEY,            -- 0..N-1, mod'd by hash(date)
  puzzle_id  TEXT NOT NULL REFERENCES puzzles(id)
);
```

### Table `corpus_meta`

One row.

```sql
CREATE TABLE corpus_meta (
  version      TEXT NOT NULL,                -- semver
  built_at     TEXT NOT NULL,                -- ISO8601
  source_hash  TEXT NOT NULL,                -- hash of input Lichess CSV
  n_puzzles    INTEGER NOT NULL,
  n_themes     INTEGER NOT NULL
);
```

## `player.sqlite`

### Table `player`

One row. Global rating plus calibration state plus vestigial preference columns.

```sql
CREATE TABLE player (
  id                    INTEGER PRIMARY KEY CHECK(id = 1),
  rating                REAL NOT NULL,
  rd                    REAL NOT NULL,
  vol                   REAL NOT NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  board_flipped_default INTEGER NOT NULL DEFAULT 0,
  sound_on              INTEGER NOT NULL DEFAULT 1,   -- vestigial, see below
  high_contrast         INTEGER NOT NULL DEFAULT 0,
  piece_set             TEXT    NOT NULL DEFAULT 'cburnett',
  reduced_motion        INTEGER NOT NULL DEFAULT 0,
  calibration_done      INTEGER NOT NULL DEFAULT 0,   -- bool
  calibration_step      INTEGER NOT NULL DEFAULT 0,   -- 0..4
  calibration_target    REAL    NOT NULL DEFAULT 1200.0
);
```

Notes:
- `sound_on`, `high_contrast`, `piece_set`, `reduced_motion`, and
  `board_flipped_default` are schema-resident but currently unread —
  preferences are backed by `Prefs` (a flat file in the app sandbox).
  Keeping the columns avoids a no-op migration.
- `calibration_*` track the 5-step binary search described in
  `specs/progression.md`. Once `calibration_done = 1` the columns are
  frozen until a Settings → Reset wipe.

### Table `theme_rating`

```sql
CREATE TABLE theme_rating (
  theme_id    TEXT PRIMARY KEY,
  rating      REAL NOT NULL,
  rd          REAL NOT NULL,
  volatility  REAL NOT NULL,
  updated_at  TEXT NOT NULL
);
```

### Table `attempts`

Every puzzle the player has ever faced.

```sql
CREATE TABLE attempts (
  puzzle_id            TEXT NOT NULL,
  resolved_at          TEXT NOT NULL,
  outcome              TEXT NOT NULL CHECK(outcome IN ('solved','failed')),
  first_wrong_move_uci TEXT,                 -- null if solved OR gave up
  rating_delta_global  REAL NOT NULL,
  solve_duration_ms    INTEGER,              -- null when unknown
  PRIMARY KEY (puzzle_id, resolved_at)
);
CREATE INDEX idx_attempts_resolved ON attempts(resolved_at);
```

`first_wrong_move_uci` is additionally null when the player invoked the
Give up button — they didn't actually try a wrong move, they ran out of
ideas. Duration is null for attempts predating the column.

### Table `review_queue`

FSRS state per puzzle that is currently scheduled for review.

```sql
CREATE TABLE review_queue (
  puzzle_id    TEXT PRIMARY KEY,
  stability    REAL NOT NULL,
  difficulty   REAL NOT NULL,
  due_at       TEXT NOT NULL,                -- ISO8601
  last_review  TEXT NOT NULL,
  last_rating  INTEGER NOT NULL              -- FSRS 1..4
);
CREATE INDEX idx_review_due ON review_queue(due_at);
```

### Table `seen_recency`

Used by selection to downweight recently-seen puzzles without excluding them.

```sql
CREATE TABLE seen_recency (
  puzzle_id  TEXT PRIMARY KEY,
  last_seen  TEXT NOT NULL
);
```

## Invariants

- `puzzles.id` is stable across corpus versions; a reshuffle of `interest` scores must not remap ids.
- Every `puzzle_themes.theme_id` has a corresponding row in `themes`.
- Prerequisite graph is a DAG; the pipeline verifies acyclicity.
- The sum of `puzzle_themes` rows for any puzzle is ≥ 1.
- `daily_index.slot` is contiguous `0..N-1`.
