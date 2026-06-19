# Chess Gym — puzzle curation pipeline

Build-time Python program that turns raw chess puzzle data into the
`puzzles.sqlite` asset the Flutter app ships. See
[`design/pipeline.md`](../design/pipeline.md) for architecture and
`design/pipeline.md` for the stage-by-stage design.

## Quick start

```bash
cd pipeline
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# smoke test on the small mock dataset (218 KB)
.venv/bin/python -m pytest tests/
```

## Running against real Lichess data

The full Lichess CSV (`lichess_db_puzzle.csv.zst`, ~50 MB compressed) is
not checked in. Fetch it from
[database.lichess.org/#puzzles](https://database.lichess.org/#puzzles)
into `pipeline/input/lichess_db_puzzle.csv` (uncompress first).

```bash
# streaming run: writes puzzles.sqlite chunk-by-chunk, 187k+ rows in ~30s
.venv/bin/python -m pipeline.run_stream \
    --lichess pipeline/input/lichess_db_puzzle.csv \
    --famous  pipeline/famous_positions.json \
    --themes  pipeline/themes.yaml \
    --out     pipeline/output/puzzles.sqlite \
    --per-theme 10000 \
    --chunk-size 500
```

Output goes to `pipeline/output/puzzles.sqlite`. To ship a new corpus:

1. Copy the file to `app/assets/puzzles/puzzles.sqlite`.
2. Bump `assetVersion` in `app/lib/data/puzzle_db.dart` — the app's
   version-marker sidecar keys on this string to trigger a fresh
   copy on-device.
3. Bump `pubspec.yaml` `version:` and `android/app/build.gradle.kts`
   `versionCode` for the store release.

## Directory layout

```
pipeline/
├── README.md                ← this file
├── requirements.txt         ← chess, pyyaml, pytest (pinned)
├── run.py                   ← legacy non-streaming entry point
├── run_stream.py            ← streaming entry point (recommended)
├── fetch_inputs.py          ← downloader for the open CC0 inputs
├── mock_lichess.py          ← generates a small synthetic CSV for testing
├── famous_positions.json    ← hand-curated classical/famous-game positions
├── themes.yaml              ← theme taxonomy
├── stages/                  ← pure, testable stages
│   ├── load.py              ← CSV + JSON → Puzzle objects
│   ├── themes.py            ← Lichess tag → canonical theme mapping
│   ├── score.py             ← interestingness features + weighted sum
│   ├── filter_and_bucket.py ← quality filter + stratified sampling
│   ├── validate.py          ← checkmate / legality / no-duplicate pass
│   └── emit.py              ← write SQLite
├── input/                   ← raw input files (gitignored except mocks)
└── tests/                   ← pytest suite (15 cases covering every stage)
```

## Tests

```bash
.venv/bin/python -m pytest tests/            # quick — ~60 ms
.venv/bin/python -m pytest tests/ -v         # verbose
```

All stages are pure — determinism is tested explicitly (same input,
same interest score and same puzzle ids).
