# User-visible data model

What the player interacts with, directly or indirectly. Physical schema is in [`design/schema.md`](../design/schema.md).

## Puzzle

| Field | Meaning |
|---|---|
| id | opaque identifier, stable across versions |
| starting position | FEN the player sees (after the scripted setup move) |
| side to move | White or Black |
| solution | ordered sequence of (solver, opponent) move pairs in UCI |
| themes | ordered list of theme ids (primary first) |
| rating | Glicko-2 puzzle rating |
| rating_deviation | Glicko-2 RD |
| difficulty | 1–10 scale derived from rating, shown to the player |
| interestingness | pre-computed score ∈ [0,1], drives corpus ranking |
| explanation | optional short prose or null |
| origin | optional attribution (game, composer, book) or null |

Puzzles are immutable. Corrections ship as a new `puzzles.sqlite` asset with a bumped version string; the app detects the bump via a lightweight `puzzles.sqlite.version` sidecar file and replaces the cached copy. (SHA256-ing the 58 MB asset on every launch triggered Android ANRs, so we skip the hash on the warm path.)

## Theme

| Field | Meaning |
|---|---|
| id | slug, e.g. `backRankMate` |
| display name | user-facing label |
| description | one-sentence hover text (unused on the current HUD) |
| floor_rating, ceiling_rating | 10th / 90th percentile puzzle ratings in the corpus; drive mastery calculation |
| importance | relative node size, legacy from the removed constellation view |

No locks, no prerequisites at runtime. The `theme_prereqs` table still exists in the schema but is ignored by the app.

## Player (local-only)

| Field | Meaning |
|---|---|
| global_rating | Glicko-2 (rating, rd, volatility) |
| theme_rating | same triplet per theme id |
| attempts | every (puzzle_id, resolved_at, outcome, first_wrong_move_uci, rating_delta) tuple |
| review_queue | FSRS card per puzzle that's been missed |
| seen_recency | last-seen timestamp per puzzle_id, for recency-aware selection |
| prefs | sound on/off, haptics on/off, auto-advance delay ms, onboarding_seen |

## Journey snapshot (derived, cached)

What the dashboard reads:

| Field | Source |
|---|---|
| global rating ± RD | player.global_rating |
| tier | bucket over global rating |
| xp | `attempts + 5 × distinct_solves` |
| level | floor((−1 + sqrt(1 + 4·xp/5)) / 2) |
| xp_to_next_level | `5·(level+1)·(level+2) − xp` |
| total solved | distinct puzzles with any solve |
| total attempts | count of attempts rows |
| missed count | puzzles whose most-recent attempt was failed |
| per-theme progress | `(total, attempts, solved, mastery, weakness, rd, retrievability, daysSincePractice, fading, selectionProbability)` |
| recommended next | the theme with the highest selectionProbability — shown as the first row of the TOP 5 panel |

Refreshed whenever the player solves or misses a puzzle, or after Settings → Reset.

## Session

Ephemeral, never persisted. No streaks, no day counters, no goals.

## Versioning

Each build bakes a `assetVersion` string (`'0.1.0+10k'` at time of writing). On launch the app compares it against a `puzzles.sqlite.version` sidecar next to the cached copy; mismatch triggers a stream-copy from the asset bundle. A sha256 sidecar is also written during that copy for any future code that wants to verify integrity, but it is NOT recomputed on warm launches. No migrations needed: the asset is read-only and schema changes ship with the app binary.
