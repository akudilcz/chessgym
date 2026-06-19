# Hints and analyze mode

What the player can see and do when they are stuck, and what they can do after a puzzle is resolved.

## During solving — no hints

The solving screen offers no hints, no "show next move", no eval bar, no arrow suggestions. The only affordances are:

- the legal-move set for any piece they touch (standard chessground highlighting)
- a **Give up** button revealed after 30 seconds of inactivity on the same position; tapping it marks the puzzle failed and reveals the solution in analyze mode

The absence of hints is deliberate. Recognition under effort is what drives chunk formation (see research items 06a, 85, 86).

## After a puzzle — analyze mode

On both solved and failed outcomes, the player may tap **Analyze**. Analyze mode opens the same board with:

- the full solution line as a PGN strip at the bottom; tap a move to jump to it, swipe to step
- freely play any legal move on the board; the app does not validate correctness, only legality
- **Reset** button to return to the puzzle starting position
- **Flip** button to flip the board
- theme tags displayed above the board
- keyboard shortcuts (iPad / Android with hardware keyboard / desktop): ← ↑ step back · → ↓ Space step forward · Home jump to start · End jump to end · F flip · R reset

No engine eval is shown. There is no "what's the best move here" function. Analyze is for the player's own exploration.

Exiting analyze returns to the post-puzzle screen.

## Explanations

Each puzzle has an optional short textual explanation stored in the shipped database (e.g. "The knight fork wins the queen and rook."). When present, the explanation is revealed on the post-puzzle screen and in analyze mode. Explanations are author-written for a curated subset; most puzzles have none, and the app shows nothing in that case rather than generating a placeholder.

Explanations are never shown before the puzzle is resolved.

## Move history strip

In analyze mode the move strip shows the solution in SAN notation with the current ply highlighted. Moves the player deviated from (when they failed) are shown in a muted color. The player's own move that caused the failure is shown with a red underline at its notation.
