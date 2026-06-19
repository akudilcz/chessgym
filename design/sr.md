# Spaced repetition — FSRS

How failed puzzles come back to the player at the right time.

## Why FSRS

SM-2 is the baseline (simple, well-understood). FSRS-4 is measurably better on the open HLR benchmarks and on Anki's own telemetry, and it is open-source. For a from-scratch app in 2026 there is no reason to ship SM-2.

If the `fsrs` Dart package is not production-ready, we hand-port the algorithm (~200 LOC, formulas published). The algorithm is deterministic and pure; porting is mechanical.

## Model

FSRS tracks two per-card state variables:

- **stability** (S): days until retrievability drops to 90%.
- **difficulty** (D): the card's inherent difficulty, ∈ [1, 10].

After a review with rating `g ∈ {Again, Hard, Good, Easy}`, the scheduler updates S and D and sets the next due date to the day retrievability next crosses the target (default 0.9).

We use default parameters for v1; a future version could fit parameters to the user's own history if enough attempts accumulate.

## Rating mapping

The app emits ratings from the solving UX, not from a review dialog. The player never taps "Again/Hard/Good/Easy" — that would be review-app UX, not puzzle UX. Instead:

| Context | Emitted rating |
|---|---|
| Failed on first exposure | Again |
| Review, solved first try | Good |
| Review, solved after one wrong move | Hard |
| Review, failed | Again |

`Easy` is never emitted. The spec accepts this trade-off: it slightly slows acceleration of very easy cards, but removes a UX burden.

## Scheduling rules

- On `Again` → reset S and D per FSRS; due_at = now + 1 minute. Short-term re-exposure is handled by the review queue ordering in `selection.dart`.
- On `Hard` / `Good` → standard FSRS update; due_at = now + next_interval_days.
- A puzzle leaves the `review_queue` only after two consecutive `Good` outcomes with S > 21 days. Data is retained in `attempts`.

## Interaction with selection

`data/selection.dart` checks `review_queue` first. Any puzzle with `due_at <= now` is served before novel puzzles, ordered by most-overdue. The player does not see a "review" label; the puzzle appears as a normal puzzle.

A cap of 10 reviews per session prevents an "all-review" day from feeling like drilling. Once 10 reviews have been served, selection falls through to novel puzzles until the next session.

## Correctness testing

- `test/unit/fsrs_test.dart` — verify S/D progression against FSRS's reference test vectors.
- `test/unit/review_queue_test.dart` — due ordering, session cap, completion rule.

## Future work

- Personalized FSRS parameters once the player has ≥ 500 reviews.
- Optional "review-only" mode for players who want pure drill.
