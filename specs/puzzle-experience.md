# Puzzle experience

What the player sees and does when solving a single puzzle.

## Entry

Player taps a puzzle (from the map, the daily queue, or the review queue). The board animates to the starting position with the side-to-move oriented at the bottom. A one-line prompt reads either "White to move" or "Black to move". No theme hint is shown by default — revealing the theme would give away the motif.

## Solving

The player drags a piece to make a move. Legal-move validation is immediate and local.

- **Correct move**: the board accepts it; the app plays the scripted opponent reply with a short animation; the player continues the line.
- **Incorrect move**: the piece snaps back, a subtle red flash on the destination square, and the puzzle is marked failed. The player may then either see the solution or retry from the start. A failed puzzle is always logged as failed regardless of subsequent retries.
- **Puzzle complete**: final move animates, board gets a green outline, and a single-line result shows rating delta (e.g. "+8"). Tap anywhere to advance to the next puzzle.

No timer. No move counter. No streak counter on-screen during solving.

**Give up**: after 30 s of inactivity on the same position, a discreet "Give up" button fades in below the board. Tapping it marks the puzzle failed (no first-wrong-move recorded) and advances to the post-puzzle screen. Any attempted move resets the 30 s clock — the button hides itself until the next idle stretch.

## Post-puzzle

One screen, minimal:
- Result (solved / failed)
- Animated rating counter with delta badge and tier label
- Optional origin label and explanation for the puzzle
- Theme tags (now revealed)
- This-puzzle history tiles (attempts, solved, failed, avg time) — shown only after the first replay
- Per-theme progress bars for every theme the puzzle belongs to, showing solved / total in each
- Primary action **Next** with a short auto-advance ticker
- Secondary icon-only actions: **Analyze** (magnifier) and **Dashboard** (grid)

The row is Analyze, Dashboard, Next from left to right. Next is the only labelled action so the row never overflows on phone widths; the secondary actions have tooltips for discoverability.

**Analyze** lets the player step through the solution line forward and backward with arrow keys / swipe, and freely explore side variations on the board (moves are validated for legality only, not correctness). No engine eval is shown — there is no engine in the app.

**Auto-advance** fires after a short delay (10.4 s default, configurable to zero to disable) so the player stays in flow; any button tap cancels it.

## Failure and repetition

Failed puzzles enter a spaced-repetition queue (SM-2). They resurface after 1 day, then 3, then 7, then 21, doubling on each success; resetting on each subsequent failure. The player sees review puzzles mixed into their normal session without being told which are reviews.

## Session shape

A session is whatever the player wants — there is no "do 10 puzzles" structure. Puzzles are served one at a time, indefinitely, until the player leaves. The next puzzle is chosen by the selection policy (see `puzzle-map.md`).

## What is explicitly absent

No ads, no accounts, no login, no social features, no chat, no leaderboards, no daily-streak pressure, no notifications pestering the player to return, no in-app purchases, no cosmetics. The app is a tool for learning.
