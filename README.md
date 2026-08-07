# Chess Gym

> A curated, fully-offline chess puzzle trainer — no accounts, no ads, no telemetry.

Chess Gym is a Flutter chess puzzle app paired with a Python build-time curation pipeline. The pipeline ingests open puzzle data (primarily the CC0 Lichess puzzle database), scores each puzzle for "interestingness," filters and stratifies it, and emits a single `puzzles.sqlite` corpus that ships inside the app as an asset. The app serves puzzles one at a time from a war-room analytics dashboard, adapts difficulty with a Glicko-2 rating, and resurfaces missed puzzles via an FSRS spaced-repetition queue.

It is built for chess players who want focused, distraction-free training: every puzzle is solved on-device, all player state lives in a local SQLite database, and there is no network client, login, or analytics SDK anywhere in the app.

## Install on Android

Chess Gym is not on any app store — you install the APK directly.

**[⬇ Download the latest APK](https://github.com/akudilcz/chessgym/releases/latest/download/chessgym.apk)** (Android 8.0 / API 26 or newer, ~85 MB — most of it is the offline puzzle database)

1. Open that link **on your phone** (or scan it from the [releases page](https://github.com/akudilcz/chessgym/releases/latest)) and let the download finish.
2. Tap the downloaded `chessgym.apk` — from the notification, or in **Files → Downloads**.
3. Android will say installs from this source are blocked. Tap **Settings**, enable **Allow from this source** for your browser (or Files app), then press back and tap **Install** again. You only do this once.
4. Play Protect may warn that the app is unknown, because it is signed with the project's own key rather than a store key. Choose **Install anyway**.

To update, download the APK again and install it over the top — your rating, history, and review queue are kept. The app never talks to the network, so it will never update itself; check the releases page when you want a newer build.

`chessgym.apk` is the 64-bit ARM build, which is what any phone made in the last decade wants. The
release also carries `chessgym-armeabi-v7a.apk` (old 32-bit ARM devices) and `chessgym-x86_64.apk`
(emulators) for the rare case.

Every push to `main` publishes a fresh signed APK to that same link (see `.github/workflows/android-release.yml`), so the download URL never changes.

## Features

- War-room HUD home screen: Glicko-2 rating with confidence interval (`1233 ±164`), tier label, level/XP, accuracy, solved and missed counters.
- Single-tap **PLAY** flow — the selection policy adaptively picks the next puzzle's theme; the player never has to choose.
- Ranked theme panels (TOP 5 / REVIEW / PRACTICE / UNEXPLORED / MASTERED) driven by per-theme rating and retention.
- Glicko-2 adaptive rating with inactivity decay, plus per-theme ratings.
- FSRS spaced-repetition queue that resurfaces failed puzzles on an expanding schedule.
- No-hint solving with a post-puzzle Analyze mode for stepping through the solution and exploring side lines (legality-validated only; no engine on device).
- Fully offline and private: no accounts, ads, telemetry, network calls, or in-app purchases.
- Build-time Python curation pipeline that scores puzzles for "interestingness" and emits a deterministic, versioned `puzzles.sqlite`.
- Pure-Dart logic package (rating, spaced repetition, selection) testable without Flutter.

## Tech stack

- **App:** Flutter (SDK `>=3.41.0`) / Dart (`>=3.9.0 <4.0.0`).
- **Key app packages:** `dartchess` (move generation/legality), `chessground` (board widget), `sqflite` + `sqflite_common_ffi` (SQLite on mobile and desktop), `flutter_riverpod` (state management), `fast_immutable_collections`, `path_provider`, `crypto`.
- **Logic package (`app_logic/`):** pure Dart — Glicko-2, FSRS, mastery, weakness, Thompson sampling, selection. Tested with the `test` package.
- **Pipeline (`pipeline/`):** Python 3 with `python-chess` (FEN/UCI parsing, legality, mate validation) and `pyyaml`; tested with `pytest`. Optional Stockfish validation at pipeline time only.

## Prerequisites

- **Flutter** `>= 3.41.0` with the Dart SDK that ships with it (Dart `>= 3.9.0`) — for the app and logic package.
- **Python 3** — for the curation pipeline (pinned deps: `chess==1.11.2`, `pyyaml==6.0.2`, `pytest==8.3.4`).
- Platform toolchains as needed: Android SDK (`compileSdk`/`targetSdk` 35) for Android builds, GTK3 for the Linux desktop build, Xcode for iOS/macOS.
- No API keys, GPU, or network access are required to build or run — the puzzle corpus (`app/assets/puzzles/puzzles.sqlite`, ~57 MB) is checked into the repo, so no pipeline run is needed for a first build.

## Installation

App (Flutter):

```bash
cd app
flutter pub get
```

Curation pipeline (Python, optional — only needed to rebuild the corpus):

```bash
cd pipeline
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Usage

Run the app (the shipped corpus is bundled, no pipeline run required):

```bash
cd app

# Desktop (Linux) — primary dev target
flutter run -d linux

# Android — requires an emulator or connected device
flutter run -d android

# Signed release APK (sideload artifact) and App Bundle (Play Store artifact)
flutter build apk --release
flutter build appbundle --release
```

Release builds are signed with the keystore described by `app/android/key.properties`
(`storePassword`, `keyPassword`, `keyAlias`, `storeFile`). That file and the keystore are
gitignored; without them the build falls back to Flutter's debug key. In CI the keystore is
supplied by the `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` repository secrets.

Web is not supported (dartchess uses 64-bit integer literals that Flutter's JS/WASM targets cannot compile).

Rebuild the puzzle corpus from real Lichess data. Download `lichess_db_puzzle.csv` from [database.lichess.org/#puzzles](https://database.lichess.org/#puzzles) into `pipeline/input/` (uncompress first), then run the streaming pipeline:

```bash
cd pipeline
.venv/bin/python -m pipeline.run_stream \
    --lichess pipeline/input/lichess_db_puzzle.csv \
    --famous  pipeline/famous_positions.json \
    --themes  pipeline/themes.yaml \
    --out     pipeline/output/puzzles.sqlite \
    --per-theme 10000 \
    --chunk-size 500
```

To ship a new corpus, copy `pipeline/output/puzzles.sqlite` to `app/assets/puzzles/puzzles.sqlite`, then bump `assetVersion` in `app/lib/data/puzzle_db.dart` (and the store version codes) so the app refreshes the on-device copy. A non-streaming entry point (`pipeline/run.py`) is also available.

## Testing

App (Flutter widget/integration tests):

```bash
cd app
flutter test
flutter analyze
```

Pure-Dart logic package (Glicko-2, FSRS, selection, mastery, weakness, Thompson, review queue):

```bash
cd app_logic
dart test
```

Pipeline (covers every stage; includes determinism checks):

```bash
cd pipeline
.venv/bin/python -m pytest tests/
```

## Project structure

- `app/` — the Flutter client. `lib/` holds `domain/`, `data/` (SQLite access, solve controller, selection/progress services, Riverpod providers), `widgets/`, and `screens/` (dashboard, solve, post-puzzle, analyze, settings, onboarding). The shipped corpus lives in `app/assets/puzzles/puzzles.sqlite`. Platform scaffolds: `android/`, `ios/`, `macos/`, `linux/`.
- `app_logic/` — standalone pure-Dart package with no Flutter dependency (`lib/src/`: `glicko2.dart`, `fsrs.dart`, `selection.dart`, `mastery.dart`, `weakness.dart`, `thompson.dart`, `review_queue.dart`), consumed by the app via a `path:` dependency.
- `pipeline/` — Python curation pipeline. `run_stream.py` (recommended) and `run.py` orchestrate the `stages/` (`load`, `themes`, `score`, `filter_and_bucket`, `validate`, `emit`). Includes `themes.yaml` taxonomy, `famous_positions.json`, `fetch_inputs.py`, `mock_lichess.py`, and a `tests/` pytest suite.
- `specs/` — user-facing feature specifications (puzzle experience, dashboard, progression, scoring, data model, offline/privacy, accessibility).
- `design/` — architecture docs (SQLite schema, pipeline, app runtime, scoring formula, Glicko-2, FSRS).
- `.github/workflows/android-release.yml` — GitHub Actions job that builds and signs the release APK on every push to `main` (and on `v*` tags) and publishes it to GitHub Releases.
- `PRIVACY.md`, `LICENSE`, `NOTICE` — privacy policy, GPL-3.0 license text, and third-party attribution.

## License

[GPL-3.0](LICENSE).

Chess Gym links `dartchess` and `chessground`, both of which are GPL-3.0, so the
combined work is GPL-3.0 as well. See [NOTICE](NOTICE) for third-party
attribution — puzzle data, linked libraries, assets, and the published
algorithms the rating and scheduling code reimplements.
