# Scoring (build-time) and selection (runtime)

Two distinct scoring mechanisms. Don't confuse them.

## 1. Interestingness — build-time, per puzzle

Each puzzle in the shipped corpus carries an `interest` ∈ [0, 1] computed by the Python pipeline and stored in `puzzles.sqlite`. Higher = better.

### Features

Per puzzle:

| Feature | Computation | Range |
|---|---|---|
| `popularity` | Lichess CSV | −100..100 |
| `nb_plays` | Lichess CSV | 1..∞ (log-scaled) |
| `rating_deviation` | Lichess CSV | 0..500 |
| `quiet_key` | first solver move is not check, not capture, not promotion | {0, 1} |
| `sacrifice` | max positive material drop on any solver move in first 4 ply (pawn units, capped 3) | 0..3 |
| `counter_intuitive` | cheap proxy: 1 if solver's first move is neither most-valuable capture nor any check | {0, 1} |
| `economy` | pieces on displayed board / 32 | 0..1 |
| `theme_rarity` | 1 / (primary-theme frequency in the input corpus) | 1..∞ |
| `mate_bonus` | solution's last solver move is mate | {0, 1} |
| `underpromotion_bonus` | any move in solution underpromotes | {0, 1} |

Z-normalize `popularity`, `log1p(nb_plays)`, `rating_deviation`, `theme_rarity` over the filtered corpus.

### Raw score

```
raw = 1.0·z_pop − 0.3·z_rd + 0.5·z_log_plays
    + 0.8·quiet_key + 1.2·sacrifice + 1.5·counter_intuitive
    − 0.4·economy + 0.6·z_rarity + 0.5·mate + 1.0·underpromo
```

### Normalization

`interest = sigmoid((raw − median(raw)) / (1.4826 · MAD(raw)))`, giving a roughly uniform [0,1] over the corpus.

Weights are tunable; defaults derived from the chess-aesthetics literature (Iqbal 2006 et al. — see NOTICE).

### Filter + stratify

After scoring, the pipeline:
- Drops Lichess rows with RD > 90, plays < 1000, popularity < 80, or `oneMove` theme only.
- Groups by primary theme × 100-wide rating bucket.
- Takes top-`interest` per bucket until each major theme reaches ~300 puzzles.

## 2. Selection — runtime, per PLAY

When the player taps PLAY, the app picks one puzzle. The policy, owned by `SelectionService`:

### Step 1: 5% missed-revisit

`_rng.nextDouble() < reviewMissedRate` (default 0.05) — if any puzzle's most-recent attempt was a failure, pick one at random from the missed set. Drives the 100%-cleared goal.

### Step 2: 20% FSRS due-review slot (when themeFocus is null)

With a further 20% chance, serve the most-overdue FSRS-scheduled puzzle. Prevents an all-review session without abandoning the SR schedule.

### Step 3: theme pick

Thompson sampling over the per-theme posterior: draw one sample from each theme's Normal(weakness, uncertainty) — uncertainty derived from the theme's Glicko RD — and serve the argmax. High-weakness themes dominate (the dashboard's `PRIORITY` theme wins most draws by construction) while high-uncertainty themes still surface for exploration, without needing an explicit share split or anti-cluster rule.

The dashboard's displayed per-theme "next puzzle" percentage is a closed-form softmax(weakness^α) approximation of this argmax distribution (α = 5, 2% per-theme floor) — computing the exact Thompson probabilities would need Monte Carlo on the UI isolate.

### Step 4: puzzle within theme

Player's theme rating → target. Query candidates where `rating ∈ [target − 150, target + 250]`, limit 200. Widen the band (±400/500 → ±900/900 → ±2400) if empty. If the theme has zero puzzles, try another theme. As a final safety net, `PuzzleDb.anyPuzzle()` returns the top-interest puzzle corpus-wide.

The candidate set is then weighted by `interest² × recency_decay` and sampled; recently-seen puzzles are down-weighted but not excluded.

### Weakness score (per theme)

```
weakness = 0.20·(1 − mastery)    // rating vs. theme floor/ceiling
         + 0.10·fail_rate        // over all attempts in this theme
         + 0.40·recent_fail_rate // rolling last-N window; falls back to fail_rate
         + 0.20·(rd / 350)       // exploration via Glicko uncertainty
         + 0.10·cold_start       // +0.2 if untouched, else 0
```

Clamped to [0,1]. Implemented in `app_logic/lib/src/weakness.dart`.

Recent performance carries the most weight deliberately: lifetime fail rate
moves too slowly to notice that a player has just started missing forks, so a
rolling window drives the practice recommendation while the lifetime rate only
anchors it. This mirrors Thompson sampling over a Glicko posterior; see NOTICE
for the citation trail.

### Difficulty 1–10 (display only)

Separate from interest/weakness. Pure function of the puzzle's Glicko rating, used for the in-solve badge:

| Difficulty | Rating range |
|---|---|
| 1 | < 800 |
| 2 | 800–999 |
| 3 | 1000–1199 |
| 4 | 1200–1399 |
| 5 | 1400–1599 |
| 6 | 1600–1799 |
| 7 | 1800–1999 |
| 8 | 2000–2199 |
| 9 | 2200–2399 |
| 10 | ≥ 2400 |

Color runs green → cyan → amber → orange → red.

## What selection never does

- Never serves the same puzzle twice in one session.
- Never requires a prerequisite — all themes are always unlocked.
- Never falls back silently to an easier puzzle after a failure. The player's rating moves; the band moves with it.
- Never surfaces an error to the player on selection failure — fallbacks always produce a puzzle.
