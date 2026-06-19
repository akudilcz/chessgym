# Progression

How the player's rating, XP, level, and mastery evolve across sessions.

## Global and per-theme rating (Glicko-2)

- **Global rating**: one Glicko-2 triplet (rating, RD, volatility).
- **Per-theme rating**: one Glicko-2 triplet per theme.
- **Seed**: rating 1200 (internal Lichess scale), RD 350, volatility 0.06 — the Glicko-2 defaults. International display rating is 300 lower (displayed 900 for an internal 1200), per the shared-puzzle-pool convention.

After every attempt (solved or failed), both the global and the primary-theme rating are updated by treating the puzzle as a rated opponent (the puzzle's CSV rating and RD). Secondary themes are updated at weight 0.5.

**First-time theme encounter** — the per-theme Glicko is seeded from the player's current GLOBAL rating (not from scratch), so the first puzzle in a new theme matches the player's actual strength, not 1200. RD stays at 350 initially until evidence accumulates.

**Inactivity decay** — when the player opens the app after a week or more of idle, RD drifts upward per Glicko-2's inactivity rule before any new attempts, so a long-absent player's rating doesn't stay artificially confident. RD is capped at the default 350 so it never inflates indefinitely.

## Calibration (first 5 puzzles)

New players skip the slow Glicko convergence via a 5-step binary-search calibration:

- Step 0 serves a puzzle at the initial target (1200 internal).
- After each outcome, the target moves by the step size (300, 300, 200, 100, 50) — up on a solve, down on a miss.
- After step 4, `calibration_done=true`, rating is set to the final target, and RD is compressed to 120 (fairly confident).
- Per-theme ratings are wiped on calibration-end so they re-seed from the calibrated global rating on next encounter.

During calibration the selector ignores weakness and just serves a puzzle at the current target rating.

## Rating display

The dashboard and the solve-screen AppBar both show rating as `R ±RD` — e.g. `1233 ±164`. The ± is the Glicko-2 standard deviation; the system is roughly 68% confident the player's true rating lies within that band.

## XP and levels

Cumulative XP is monotonic — it only ever goes up:

- `+1 XP per attempt` (solved or failed).
- `+5 XP per solve`.

So even a session of all misses moves the XP bar. Level is derived from XP via a quadratic curve:

- Level L is reached at `XP = 5 · L · (L + 1)`.
- L1 at 10 XP · L2 at 30 XP · L3 at 60 XP · L4 at 100 XP · …

## Tier

Tier is a display layer on top of the global rating:

| Tier | Rating floor |
|---|---|
| Beginner | 0 |
| Novice | 900 |
| Intermediate | 1200 |
| Advanced | 1500 |
| Expert | 1800 |
| Master | 2100 |
| Grandmaster | 2400 |

Each tier has its own color and icon, consistent across the app.

## Mastery visualization

For each theme, mastery ∈ [0, 1] is:

```
mastery(theme) = clamp01( (rating − theme_floor) / (theme_ceiling − theme_floor) )
```

where floor/ceiling are the 10th/90th-percentile puzzle rating for that theme in the shipped corpus.

Mastery, along with attempts, success rate, RD, recent performance, and a retention model, feeds the **weakness score**. Weakness plus fading-retention in turn drives which of the five dashboard panels the theme appears in — REVIEW, TOP 5, PRACTICE, UNEXPLORED, or MASTERED. See `specs/puzzle-map.md` for the panel semantics.

## 100% completion

The player can eventually clear every puzzle. A puzzle is "cleared" if the player's most recent attempt on it was a solve; "missed" if it was a fail.

- The **MISSED** stat on the dashboard shows the count of not-yet-cleared puzzles.
- Selection rolls a 5% chance per turn of serving a missed puzzle instead of a new focus-area one, so misses resurface naturally.
- When the player re-solves a missed puzzle, it drops from the MISSED bucket. No user action needed.
- MISSED turns green in the HUD when zero.

## No streaks, no daily goals

There is intentionally no daily-streak mechanic, no session goal, no XP multiplier, no "days in a row" counter. XP goes up. Rating changes. MISSED eventually drops to zero. That's all the pressure the app applies.

## Reset

Settings → Reset progress wipes all attempts, review queue, and ratings back to defaults. The shipped puzzle corpus itself is untouched.
