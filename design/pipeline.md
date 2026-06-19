# Pipeline

Build-time Python program that ingests raw chess puzzle data, scores and filters it, and emits the `puzzles.sqlite` the app ships.

## Goals

- Single command produces a versioned `puzzles.sqlite`.
- Deterministic given the same inputs: same puzzle ids, same interestingness scores.
- Pure Python + `python-chess`; no shipped engine on the device.
- Stockfish is used at pipeline time for validation on a subset; not required for the vast majority of puzzles (Lichess puzzles are already engine-validated).

## Inputs

- `pipeline/input/lichess_db_puzzle.csv[.zst]` — primary source, CC0.
- `pipeline/input/classical_studies.pgn` — curated Troitsky/Kubbel/Réti/Saavedra corpus, public domain.
- `pipeline/input/famous_positions.json` — 30-ish hand-curated entries (Immortal, Evergreen, Deep Blue, etc.) each with FEN, solution line, and origin label.
- `pipeline/input/themes.yaml` — the canonical theme taxonomy: id, display name, description, importance, prerequisite edges. Sourced from Lichess themes glossary + composer mate-pattern names.

Inputs are not checked into git. A `fetch_inputs.py` script downloads the CC0 CSV and classical PGNs on demand.

## Stages

```
    raw inputs
        │
        ▼
   1. parse         — python-chess parses FEN/UCI, validates legality
        │
        ▼
   2. normalize     — synthesize puzzle_id for non-Lichess items; apply setup move
        │
        ▼
   3. theme remap   — Lichess themes → canonical ids; compute primary theme
        │
        ▼
   4. score         — compute interestingness features per puzzle
        │
        ▼
   5. filter        — apply quality gates
        │
        ▼
   6. bucket        — stratified sample to hit coverage guarantees
        │
        ▼
   7. (optional) validate — run Stockfish at depth 25 on a random 1% sample
        │
        ▼
   8. emit          — write puzzles.sqlite + log coverage report
```

### Stage 4 — interestingness features

Computed per puzzle, all deterministic:

- `quiet_key` — 1 if first solver move is not check, not capture, not promotion; else 0.
- `sacrifice` — material lost on any solver move in the first 2 ply, in pawn units.
- `counter_intuitive` — 1 minus the fraction of a shallow search's top-3 candidate moves (depth 6) that coincide with the true first move. Computed with python-chess's built-in move ordering heuristics, not Stockfish (to stay fast).
- `economy` — `pieces_on_board / 32`.
- `theme_rarity` — `1 / frequency(primary_theme)`, where frequency is the theme's share of the full input corpus.
- `mate_bonus` — 1 if solution ends in `#`.
- `underpromotion_bonus` — 1 if any move in the solution underpromotes.
- Normalized `popularity`, `log(plays)`, `rating_deviation` pulled from the CSV.

Score formula (v0, per `specs/scoring.md`):

```
interest_raw = 1.0 * z(popularity)
             + 0.5 * z(log1p(nb_plays))
             - 0.3 * z(rating_deviation)
             + 0.8 * quiet_key
             + 1.2 * min(sacrifice, 3)
             + 1.5 * counter_intuitive
             - 0.4 * economy
             + 0.6 * z(theme_rarity)
             + 0.5 * mate_bonus
             + 1.0 * underpromotion_bonus
```

Then `interest = sigmoid((interest_raw - mean) / std)` mapped to [0, 1].

Weights are tunable. A calibration harness (`pipeline/calibrate.py`) grid-searches weights against a held-out set of Popularity≥95 puzzles treated as the gold standard.

### Stage 5 — filter

Drop puzzles where any of:

- `rating_deviation > 90`
- `nb_plays < 1000` (for Lichess tier only)
- `popularity < 80` (for Lichess tier only)
- themes include `oneMove` only
- `interest < 0.35` (after z-normalization)

Classical studies and famous positions bypass this filter; they are guaranteed in by origin.

### Stage 6 — bucket

Stratified sample to guarantee coverage. For each theme and each 100-rating bucket from 600 to 2400, keep the top-interest K puzzles until the theme reaches its target count (1,000 per major theme, 300 per minor theme). Oversample by 20% so ties can be broken deterministically.

### Stage 7 — optional Stockfish validation

For a 1% random sample, run Stockfish at depth 25 and check that the recorded solution is the best move. Log mismatches; drop if the engine disagrees materially (eval delta > 100 cp). Full-corpus validation is optional and expensive; the 1% audit is the regression check.

### Stage 8 — emit

Write `puzzles.sqlite` per `design/schema.md`. Write `coverage.json` alongside for CI: per-theme counts, rating histogram, interestingness histogram. Fail the build if any spec guarantee is violated (e.g. a major theme has <1,000 puzzles after filtering).

## Layout

```
pipeline/
  fetch_inputs.py
  run.py                # orchestrator
  stages/
    parse.py
    normalize.py
    themes.py
    score.py
    filter.py
    bucket.py
    validate.py
    emit.py
  input/                # gitignored
  output/               # gitignored
  themes.yaml
  classical_studies.pgn # small, checked in
  famous_positions.json # small, checked in
  tests/
```

## Determinism

Random sampling seeded from the input CSV hash, not from wall-clock. Same inputs → byte-identical `puzzles.sqlite`.
