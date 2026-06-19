# App architecture

Flutter runtime for the Chess Gym HUD.

## Stack

- **Flutter 3.41.7 / Dart 3.9**
- **dartchess 0.12** — move generation and legality
- **chessground 7** — board widget, drag-and-tap move input, animated last-move highlight, promotion picker
- **fast_immutable_collections 11** — immutable IMap/ISet used by chessground
- **sqflite + sqflite_common_ffi** — SQLite on all platforms including desktop
- **path_provider, path** — app sandbox directory lookup
- **flutter_riverpod** — state management
- **crypto** — sha256 sidecar for the asset-copy path
- **chesspuzzle_logic** (path dep) — pure-Dart rating, FSRS, weakness, selection

No analytics, ads, telemetry, network clients, or accounts SDKs. No third-party plugins beyond the ones listed.

## Directory layout

```
app/
  lib/
    main.dart                  WidgetsFlutterBinding + sqfliteFfi init + ProviderScope
    app.dart                   MaterialApp with the war-room theme
    theme/app_theme.dart       WR.* palette, monospace text, dark-only
    domain/
      puzzle.dart              Puzzle, ThemeInfo
      rating_tier.dart         Tier enum + color/icon + difficulty1to10()
    data/
      prefs.dart               File-backed k/v (no shared_preferences)
      puzzle_db.dart           Read-only shipped DB, versioned asset copy
      player_db.dart           Mutable player state, Glicko inactivity decay on open
      puzzle_controller.dart   Two-step solve state machine
      selection_service.dart   Thompson theme pick + candidate band + review pick
      progress_service.dart    JourneySnapshot for the HUD (softmax display %)
      providers.dart           Riverpod providers
    widgets/
      animated_number.dart     Tween-on-change tabular counter
      fast_fade_route.dart     150 ms fade transition for solve ⇄ post-puzzle
      live_dot.dart            Pulsing HUD indicator
      tier_bar.dart            Full-width band-coloured rating scale
    screens/
      map/                     War-room dashboard (MapScreen)
      solve/                   Board + controller
      post_puzzle/             Result screen with animated rating ticker
      analyze/                 Solution walker (no engine)
      settings/                Prefs, reset, About, Licenses
      onboarding/              First-run intro
  assets/
    puzzles/puzzles.sqlite
    icon/icon.png
  test/
```

## Screens

```
   first launch?
         │
         ▼
   ┌───────────┐    ┌──────────────────┐    ┌───────────┐    ┌─────────────┐
   │Onboarding │───▶│    Dashboard     │───▶│   Solve   │───▶│ PostPuzzle  │
   │  (3 slides)    │  war-room HUD    │◀───│  fade ⇄   │    │  autoAdvance│
   └───────────┘    └──────────────────┘    └───────────┘    └──────┬──────┘
                             ▲                   │                  │
                             │                   ▼                  │
                        ┌───────────┐      ┌──────────┐             │
                        │ Settings  │      │ Analyze  │             │
                        └───────────┘      └──────────┘             │
                             ▲                                      │
                             └──────────────────────────────────────┘
                           (Dashboard | Next | Analyze buttons)
```

- **Dashboard** is the home. Tier-coloured hero rating (tappable, info popup), full-width tier bar, XP line, 2×2 stat tiles (each tappable for info), and up to five theme panels (**TOP 5** / **REVIEW** / **PRACTICE** / **UNEXPLORED** / **MASTERED**) with per-panel info popups. Single floating action: **PLAY**.
- **Solve** is the board. AppBar shows compact difficulty badge + rating. Board accepts both drag-and-drop and tap-to-select-then-tap-destination input.
- **PostPuzzle** shows a 500 ms rating-delta animation, this-puzzle stats (once replayed), per-theme progress bars for every theme the puzzle belongs to, and three actions: icon-only Analyze, icon-only Dashboard, labelled Next. Auto-advance countdown is a hairline progress bar at the bottom.
- **Analyze** steps through the solution; no engine eval.
- **Settings** — sound/haptics toggles, auto-advance picker, reset, About popup, Licenses page.

## Transitions

Solve ⇄ PostPuzzle uses `FastFadeRoute` (150 ms fade, opaque) instead of Material's default slide. The slide was fighting the rating-counter animation and made repeat play feel sticky.

## Game loop

1. Dashboard renders from the cached `JourneySnapshot`.
2. User taps **PLAY**.
3. `SolveScreen` calls `SelectionService.pickNext(themeFocus: null, snapshot: <journey>)`. Fallback chain guarantees a puzzle is always returned.
4. `PuzzleController` applies the setup move, hands control to the player.
5. Each tap/drag goes through chessground → `onMove` → `PuzzleController.tryMove`.
   - On the player's correct move, the state machine returns `MoveOutcome.opponentReply`; the UI waits 220 ms (matches chessground animation), plays the reply, hands control back.
   - On a wrong move, the move is still applied to the display position so the player sees the piece land on its destination, then `_applyMove` waits `_animDuration + 500 ms` before running `_finish(solved: false)`.
6. `_finish` updates global + per-theme Glicko, records the attempt, updates the FSRS queue (including drain on successful solves of previously missed puzzles), and fades to `PostPuzzleScreen`.
7. After the auto-advance timer, `PostPuzzleScreen` fades back to a new `SolveScreen` and the loop repeats.

## Performance

The journey snapshot is the hot path — computed on cold start and again after every solve. Work that was on the UI isolate and moved off or removed:

- `PuzzleDb.puzzleThemesMap()` (395k rows) is cached for the PuzzleDb lifetime. Cold hit ~1–1.4 s on mid-range Android; warm is instant.
- `PuzzleDb.listThemes()` and `themeTotals()` are cached identically.
- `PlayerDb.aggregateAttempts` is a single ordered scan of `attempts` plus a Dart pass using the cached themes map — produces solved-by-theme, attempted-by-theme, recent-fail-rate and last-attempt-per-theme in one walk. Typical warm call 1–5 ms.
- Dashboard selection-% was Monte-Carlo over Thompson samples (2000 trials × 26 themes of Box-Muller); replaced with a closed-form softmax. Same ordering, microseconds instead of ~100 ms.
- `SelectionService.pickNext` accepts a precomputed snapshot so it doesn't re-run the journey computation on every puzzle transition.
- `PuzzleDb.candidatesForTheme` no longer `GROUP_CONCAT`s themes for each candidate — 472 ms → 172 ms on a Samsung A56. Themes for the picked puzzle are loaded separately via `byId` (cheap PK lookup).

Profiling hooks: solve, snapshot, and pick paths emit `[FINISH]`, `[SNAPSHOT]`, `[PICK]` log lines with a per-step millisecond breakdown — visible via `adb logcat -s flutter`.

## Robustness

- Zero user-facing error screens. Every DB-access path has a cascading fallback; worst case, selection returns the top-interest puzzle corpus-wide, guaranteeing PLAY always yields a puzzle.
- `sqflite_common_ffi` is initialized on all desktop platforms at startup in `main.dart`.
- Asset DB is replaced on-device when its version marker differs from the shipped one (we do NOT sha256 the 58 MB file on every launch; the per-launch hash was an ANR on Android).
- Glicko-2 inactivity decay applied on first open after ≥7 days, capped at RD 350.

## Platforms

- **iOS**: scaffolded (`ios/`), bundle id `com.digitalcaffeine.chessgym`.
- **Android**: primary mobile target, `applicationId` and `namespace` both `com.digitalcaffeine.chessgym`, `compileSdk`/`targetSdk` 35 (required by Play Store as of August 2025), adaptive icons, debug and signed-release both build clean.
- **macOS**: scaffolded (`macos/`).
- **Linux**: desktop build verified (GTK3). Primary dev target.
- **Windows**: scaffolded via Flutter defaults; untested.
- **Web**: not supported — dartchess uses 64-bit int literals that neither Flutter JS nor WASM can compile at current versions.

## Testing

- `app/test/puzzle_controller_test.dart` — state machine.
- `app/test/puzzle_db_test.dart` — SQL shape round-trip via in-memory ffi.
- `app/test/player_db_test.dart` — attempts, review queue upsert/remove, reset.
- `app_logic/test/*.dart` — Glicko-2 (paper example), FSRS, Selection, Mastery, Weakness, ReviewQueue.
- `pipeline/tests/test_pipeline.py` — taxonomy, scoring, filter/bucket, validation, emit.

`flutter analyze`: zero errors, zero warnings.
