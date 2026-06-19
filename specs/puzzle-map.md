# Dashboard (war-room HUD)

The home screen and the model of progress the player sees across sessions.

## Shape: war-room analytics HUD

The home is a mission-control dashboard, not a navigable map. Pitch-black canvas, monospace font, neon accents. Every statistic the player cares about is visible at a glance:

- Current rating and tier, with the Glicko-2 confidence interval as `1233 ±164`.
- Level and XP progress to next level.
- Total puzzles solved, accuracy percent, currently-missed count.
- Per-theme tables ranked by selection probability.

No tiles grid, no decorative cards. This is deliberate: the player reads this like a ticker, not a menu.

## Unlocked by default

Every theme is available from session one. There is no prerequisite graph, no locked nodes, no unlock sequence. The theme DAG in the shipped corpus remains for grouping purposes only.

## Hero rating, tappable

The rating block at the top of the dashboard is:

- Big rating number, tier-coloured, with `±RD` next to it
- Tier label below (BEGINNER, NOVICE, INTERMEDIATE, ADVANCED, EXPERT, MASTER, GRANDMASTER)
- Small info icon signalling the block is tappable

Tapping opens a dialog explaining Glicko-2, the ±RD credible interval, and what the tier label means.

## Stat tiles

A 2×2 grid (SOLVED / ACCURACY / MISSED / LEVEL) sits below the tier bar. Each tile is tappable and opens a dialog explaining that specific metric (e.g. "distinct puzzles you have solved at least once; re-solves don't double-count"). Label and value are both centered.

## Ranked theme panels

Themes are bucketed into up to five panels, shown in this order. Every panel header has an info icon that opens a dialog explaining the bucket.

- **TOP 5** (amber) — the five themes most likely to be served on the next PLAY tap, across every bucket. One-glance "what should I work on". Rows here are a highlight copy of rows that also appear in REVIEW / PRACTICE / UNEXPLORED; `MASTERED` themes rarely surface here.
- **REVIEW** (amber) — themes the player has practised before, now fading from memory (retention below 85%). 30% of next puzzles come from this bucket when non-empty.
- **PRACTICE** (cyan) — themes the player is actively learning; mixed results, rating climbing. The bulk of next puzzles come from here. Always shown, even when empty.
- **UNEXPLORED** (violet) — themes the player has never attempted.
- **MASTERED** (green) — themes consistently cleared, retention above 85%. Resurfaces only when retention decays.

REVIEW, UNEXPLORED, and MASTERED hide themselves entirely when empty so the page stays short. PRACTICE stays visible with an em dash if there's no data yet.

### Row shape

Each row is compact: rank number · THEME NAME · optional fading-hourglass icon · selection% · first-try success %. No solved/total count, no horizontal progress bar — the name needs the room on a phone.

Colours: selection% is amber when ≥20%, cyan when ≥5%, muted otherwise. Success% is red < 50%, amber < 75%, green otherwise.

Sorting within each panel is selection-probability descending, so the first row is always the most-likely next puzzle from that bucket.

## The PLAY button

The player does not pick a theme. They tap **PLAY** (prominent cyan floating button, always on the dashboard) to start a single puzzle. The selection policy decides the theme adaptively — see `specs/scoring.md` and `design/scoring.md`.

## The 100% goal

A puzzle is "cleared" when the player's most recent attempt on it was a solve. Missed puzzles — those whose last attempt was a failure — accumulate in a **MISSED** stat on the HUD and drop out when re-solved. The selection policy rolls a 5% probability each turn of serving a missed puzzle instead of a new one, so no missed puzzle is forgotten forever, and the player eventually drives MISSED to zero.

## Stats always visible

- **RATING ±RD**: current Glicko-2 rating, with uncertainty band.
- **LEVEL**: derived from cumulative XP. 1 XP per attempt + 5 XP per solve so the bar always moves forward, regardless of outcome.
- **SOLVED**: distinct puzzles ever solved.
- **ACCURACY**: total solved / total attempts, as a percent.
- **MISSED**: puzzles whose last outcome was a failure (green when zero).
- **XP bar**: progress to next level.
- **TIER bar**: rating progress to next tier (Beginner → Novice → … → Grandmaster).

## Loading state

On first launch of a session the dashboard hydrates a 395k-row theme map; the spinner is paired with "Warming up the puzzle library…" so the first-paint wait reads as intentional rather than frozen. Subsequent snapshots are cached and paint immediately.

## Daily puzzle

Removed from the shipping app. The PLAY flow and the 100% goal replace the "habit hook" role that daily puzzles typically play.
