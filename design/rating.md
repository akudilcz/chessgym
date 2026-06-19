# Rating — Glicko-2

The player's rating system. One global rating plus one per-theme rating, all Glicko-2.

## Why Glicko-2

Elo doesn't track uncertainty; a new player's 800 carries no signal about confidence. Glicko-2 tracks rating, RD (deviation), and volatility. We want adaptive difficulty that responds quickly early on and stabilizes over time — Glicko-2 does this natively.

Alternatives considered:

- **TrueSkill** — optimized for multi-player matches. Our context is 1v1 (player vs puzzle). Unnecessary complexity.
- **Item Response Theory** — more principled for item-level difficulty calibration, but assumes a static item pool and tightly-bound model; harder to tune and explain. Good candidate for v2 difficulty calibration on the pipeline side, not the player side.

## Parameters

From the Glicko-2 spec:

- Initial rating: 1500 in Glickman's paper. We override to **800** to match beginner chess ratings and align with Lichess puzzle rating scale.
- Initial RD: 350.
- Initial volatility: 0.06.
- System constant τ: 0.5 (conservative; reduces volatility swings for hobbyist context).
- Rating period: **each puzzle attempt is its own rating period**. This differs from the paper's batch approach, but matches how solo-training rating systems work in practice (e.g. Lichess puzzle rating).

## Per-theme ratings

The primary theme of each puzzle is updated at full weight. Secondary themes (position 2+ in `puzzle_themes`) are updated at weight 0.5 by treating the puzzle as a half-weight game.

Per-theme RD floors are higher (RD_min = 60) than the global RD floor (RD_min = 30), so theme ratings stay responsive and the constellation mastery visualization remains lively.

## Puzzle as opponent

The puzzle's `rating` and `rating_dev` from the CSV are used as the opponent's rating and RD. The puzzle's volatility is unused (we do not update puzzle ratings).

## Update procedure

1. On attempt resolved:
   - outcome `solved` → score 1
   - outcome `failed` → score 0
   - (No draws.)
2. Compute new (r, RD, σ) for global rating using the Glicko-2 update with a single game.
3. Compute the same for the primary theme's rating using the same attempt.
4. Compute half-weight update for each secondary theme by treating the attempt as a single game with score {0, 0.5, 1} matched to outcome {failed, — , solved}; the half-weight comes from the custom update for partial rating periods.
5. Persist to `player.sqlite` (`player` and `theme_rating`).

## Rating delta shown

The global rating delta (rounded to integer) is shown post-puzzle as "+8" or "-5". No per-theme delta is shown; mastery is shown in the constellation at next view.

## Correctness testing

`test/unit/glicko2_test.dart` must reproduce the worked example in §1 of Glickman's 2013 paper (the canonical verification problem). Any refactor must keep this test passing.

## Export / reset

Resetting via Settings wipes all rows in `player` and `theme_rating` and reseeds defaults. No partial reset (e.g. "forget one theme") — the player's mental model is one cohesive progress state.
