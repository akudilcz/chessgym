# Chess Gym — Flutter app

The mobile client. Consumes `puzzles.sqlite` (bundled as an asset,
produced by the `../pipeline/` Python tool) and maintains on-device
`player.sqlite`.

## Layout

```
lib/
  main.dart                       bootstrap + sqflite_ffi init + ProviderScope
  app.dart                        MaterialApp + war-room theme
  theme/app_theme.dart            Colors, palettes
  domain/
    app_info.dart                 AppInfo.version / name / legalese
    puzzle.dart                   Puzzle, ThemeInfo
    rating_tier.dart              Tier enum + difficulty1to10()
  data/
    puzzle_db.dart                Read-only shipped DB, cached lookups
    player_db.dart                Mutable player state + aggregate pass
    puzzle_controller.dart        Two-step solve state machine
    selection_service.dart        Thompson pick + candidate band + profile
    progress_service.dart         JourneySnapshot for the HUD
    prefs.dart                    File-backed KV
    providers.dart                Riverpod providers
  widgets/
    animated_number.dart          Tabular counter w/ reduce-motion bypass
    fast_fade_route.dart          150 ms fade transition solve ⇄ post-puzzle
    live_dot.dart                 Pulsing / static HUD indicator
    tier_bar.dart                 Full-width rainbow tier scale
  screens/
    map/                          War-room dashboard (the home)
    solve/                        Board + controller + give-up timer
    post_puzzle/                  Result screen with animated rating
    analyze/                      Solution walker with keyboard shortcuts
    settings/                     Prefs, reset, About, Licenses
    onboarding/                   First-run three-slide intro
```

The pure logic (Glicko-2, FSRS, selection, mastery, Thompson) lives in
`../app_logic/` as a standalone Dart package that can be tested
without Flutter. This app depends on it via `path:`.

## Build

Requires **Flutter ≥ 3.41** / Dart 3.9+. The shipped puzzle corpus
(`assets/puzzles/puzzles.sqlite`, ~57 MB for 187k puzzles) is checked
in — no pipeline run needed for a first build.

```bash
cd app
flutter pub get

# Desktop (Linux) — primary dev target:
flutter run -d linux

# Android — requires an emulator or connected device:
flutter run -d android

# Signed release AAB (what goes to Play):
flutter build appbundle --release
```

## Tests

```bash
cd app
flutter test                      # 16 tests
flutter analyze                   # 0 errors, 0 warnings
```

Pure logic tests live separately in `../app_logic/test/` (35 tests) —
run with `dart test` from that directory. Pipeline has its own suite
(`pipeline/tests/`, 15 cases) run via `pytest`.

## Profiling

The solve, snapshot, and pick paths emit `[FINISH]`, `[SNAPSHOT]`, and
`[PICK]` log lines with per-step millisecond breakdowns. Filter via
`adb logcat -s flutter:I` during a debug run to see the hot-path
numbers in real time.

## Status

Release AAB builds clean at
104 MB (under Play's 150 MB soft cap).
