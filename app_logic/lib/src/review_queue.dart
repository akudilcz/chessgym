import 'fsrs.dart';

/// True when a card graduates out of the review queue: two consecutive
/// Good-or-better outcomes with stability past 21 days (design/sr.md).
/// Shared by [ReviewQueue] and the app's solve-resolution path so the rule
/// cannot drift between them.
bool graduatesReview({
  required Rating rating,
  required Rating? previousRating,
  required double stability,
}) {
  const good = [Rating.good, Rating.easy];
  return good.contains(rating) &&
      previousRating != null &&
      good.contains(previousRating) &&
      stability > 21.0;
}

/// A tiny wrapper: pop the most-overdue card, apply the solve-outcome
/// rating, and reschedule. See specs/progression.md for the outcome mapping.
class ReviewQueue {
  final Fsrs fsrs;
  final Map<String, FsrsCard> cards = {};
  final int sessionCap;
  int servedThisSession = 0;

  ReviewQueue({required this.fsrs, this.sessionCap = 10});

  /// Add a new failure. If the card is already scheduled, this is a lapse of
  /// an existing card, not a first exposure — rate it Again in place rather
  /// than replacing it, which would erase its accumulated FSRS history.
  void onFirstFailure(String puzzleId, DateTime now) {
    final existing = cards[puzzleId];
    if (existing != null) {
      fsrs.review(existing, Rating.again, now);
      return;
    }
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
    final previous = c.lastRating;
    fsrs.review(c, rating, now);
    servedThisSession += 1;
    if (graduatesReview(
      rating: rating,
      previousRating: previous,
      stability: c.stability,
    )) {
      cards.remove(puzzleId);
    }
  }

  void resetSession() {
    servedThisSession = 0;
  }
}
