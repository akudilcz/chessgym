# Scoring and selection (what the player experiences)

## The promise

Every puzzle you see was picked for a reason. No filler, no random "beginner trap" puzzles served next to a grandmaster study. The corpus is curated, and selection is adaptive.

## Two scores

- **Interestingness** (0 to 1, invisible): a build-time quality score. Drives which puzzles enter the shipped corpus and which rank at the top of their theme bucket. Higher = more likely to be surprising, aesthetic, or pedagogically rich.
- **Difficulty** (1 to 10, visible): a per-puzzle rating-to-slider mapping, shown on the solve-screen AppBar as a `D1`…`D10` badge. Lets you see at a glance how hard this particular puzzle is, independent of your own rating.

## How the next puzzle is chosen

Every time you tap **PLAY**:

1. **During calibration** (first 5 puzzles), the selector ignores weakness entirely and just serves a puzzle at the target rating. A five-step binary search pegs your rating in 5 attempts instead of 15–20.
2. **5% of the time** post-calibration, pick a puzzle from your MISSED list — one you failed and haven't re-solved. Drives toward the 100%-cleared goal.
3. **20% of the time** (within the remaining 95%), if there's an FSRS review card due, serve that instead. Prevents forgotten lessons.
4. Otherwise, pick a theme via **Thompson sampling**:
   - **30%** of the time, sample only over *fading* themes (retention < 85%). If you have fading themes, they jump the queue; otherwise this branch falls back to the full pool.
   - **70%** of the time, sample over the full available pool (any theme that still has unsolved puzzles).
   - Thompson sampling draws one N(weakness, uncertainty) sample per theme and picks the argmax. **Uncertainty is driven by the theme's Glicko-2 RD**: fresh themes (RD ~ 350) get wide posteriors and explore freely; converged themes (RD ~ 60) sample tightly around their weakness point estimate. A 0.15 floor keeps even fully-converged themes occasionally winning.
5. Within that theme, pick a puzzle from a rating band biased ABOVE your per-theme rating (aiming at the ~75–85% challenge zone), weighted toward high interestingness and away from recently-seen puzzles.

If at any step the pool is empty (shouldn't happen on the shipped corpus), the selector widens the rating band upward, then tries other themes, then pulls the top-interest puzzle corpus-wide. The player never sees an error.

## Dashboard selection percentages

The `selection %` shown on each theme row is the dashboard's estimate of how likely that theme is to be the next one served. It's a **closed-form softmax** over weakness with the same 30% due / 70% pool split as the selector — not a Monte Carlo of Thompson samples. It matches Thompson's ordering monotonically and renders in microseconds instead of ~100 ms.

Expect values in the range 2% (floor) to ~30–50% for a strongly-favoured theme.

## Weakness (what the ranking is based on)

A theme's weakness score blends:

- How far your theme rating is below the theme's 90th-percentile puzzle rating.
- How often you've failed puzzles in that theme recently.
- How uncertain the system is about your skill there (high Glicko RD = more exploration).
- A small cold-start bonus for themes you've never attempted.
- A forgetting boost if your retention model predicts the theme has faded below 85%.

## What selection never does

- Never serves the same puzzle twice in one session.
- Never requires unlocking a theme — everything's available from day one.
- Never lowers difficulty silently after a miss; your rating moves, and the band moves with it.
- Never uses any signal from other players — no aggregated analytics, no leaderboards. Your data stays on your device.
