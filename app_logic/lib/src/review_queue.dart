import 'fsrs.dart';

/// A tiny wrapper: pop the most-overdue card, apply the solve-outcome
/// rating, and reschedule. See specs/progression.md for the outcome mapping.
class ReviewQueue {
  final Fsrs fsrs;
  final Map<String, FsrsCard> cards = {};
  final int sessionCap;
  int servedThisSession = 0;

  ReviewQueue({required this.fsrs, this.sessionCap = 10});

  /// Add a new failure (first exposure).
  void onFirstFailure(String puzzleId, DateTime now) {
    final c = FsrsCard();
    fsrs.review(c, Rating.again, now);
    cards[puzzleId] = c;
  }

  /// Return due puzzle ids in FIFO of due_at (most-overdue first), up to
  /// remaining session cap.
  List<String> dueIds(DateTime now) {
    if (servedThisSession >= sessionCap) return const [];
    final due = cards.entries
        .where((e) => e.value.due != null && !e.value.due!.isAfter(now))
        .toList()
      ..sort((a, b) => a.value.due!.compareTo(b.value.due!));
    return due
        .take(sessionCap - servedThisSession)
        .map((e) => e.key)
        .toList();
  }

  /// Record a review outcome for a scheduled card.
  void onReview({
    required String puzzleId,
    required Rating rating,
    required DateTime now,
  }) {
    final c = cards[puzzleId];
    if (c == null) return;
    fsrs.review(c, rating, now);
    servedThisSession += 1;
    // Completion: two consecutive Goods with stability > 21.
    if (rating == Rating.good && c.stability > 21.0 && c.reps >= 3) {
      cards.remove(puzzleId);
    }
  }

  void resetSession() {
    servedThisSession = 0;
  }
}
