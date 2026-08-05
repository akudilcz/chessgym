import 'dart:math' as math;

/// FSRS-4 scheduler. Minimal pure-Dart port, sufficient for scheduling
/// reviews of failed puzzles.
///
/// Rating enum:
///   1 = Again, 2 = Hard, 3 = Good, 4 = Easy
enum Rating { again, hard, good, easy }

int ratingToInt(Rating r) => r.index + 1;

/// Default FSRS-4.0 weights (w[0..16]), from the fsrs4anki v4.4.1 scheduler.
///
/// These must stay matched to the FSRS-4 formulas below. The later FSRS-5
/// parameter set is NOT interchangeable: FSRS-5 redefines w[5] as an exponent
/// in `D0 = w4 - e^(w5*(G-1)) + 1` where FSRS-4 uses it as a linear slope, so
/// pairing FSRS-5 weights with these formulas distorts initial difficulty by
/// 1.4-1.8x and compounds through every subsequent interval.
const List<double> defaultWeights = [
  0.4, 0.6, 2.4, 5.8,
  4.93, 0.94, 0.86, 0.01,
  1.49, 0.14, 0.94, 2.18,
  0.05, 0.34, 1.26, 0.29,
  2.61,
];

class FsrsCard {
  double stability; // days to R=0.9
  double difficulty; // [1, 10]
  DateTime? lastReview;
  DateTime? due;
  Rating? lastRating;
  int reps;
  int lapses;

  FsrsCard({
    this.stability = 0.0,
    this.difficulty = 0.0,
    this.lastReview,
    this.due,
    this.lastRating,
    this.reps = 0,
    this.lapses = 0,
  });

  /// A card rehydrated from storage may carry reps == 0 (the counter is not
  /// persisted) but a non-null lastReview; it has history and must not be
  /// re-initialized, or its accumulated stability is silently discarded.
  bool get isNew => reps == 0 && lastReview == null;
}

class Fsrs {
  final List<double> w;
  final double requestRetention;

  Fsrs({this.w = defaultWeights, this.requestRetention = 0.9});

  /// Review a card with [rating] at time [now]. Mutates the card in place and
  /// returns the interval in days until next review.
  double review(FsrsCard c, Rating rating, DateTime now) {
    if (c.isNew) {
      _initCard(c, rating);
    } else {
      _updateCard(c, rating, now);
    }
    final interval = _nextInterval(c.stability);
    c.due = now.add(Duration(
      milliseconds: (interval * 24 * 3600 * 1000).round(),
    ));
    c.lastReview = now;
    c.lastRating = rating;
    c.reps += 1;
    if (rating == Rating.again) c.lapses += 1;
    return interval;
  }

  void _initCard(FsrsCard c, Rating rating) {
    c.difficulty = _initDifficulty(rating);
    c.stability = _initStability(rating);
  }

  void _updateCard(FsrsCard c, Rating rating, DateTime now) {
    // A review timestamped before the last one — clock change, timezone
    // shift, backfilled history — would make retrievability exceed 1 and
    // drive stability negative, poisoning every later update.
    final elapsedDays = c.lastReview == null
        ? 0.0
        : math.max(0.0, now.difference(c.lastReview!).inSeconds / 86400.0);
    // A card rehydrated with stability 0 but reps > 0 lands here; pow(0, -w)
    // is infinite and 0 * infinity is NaN, which clamps to the MAXIMUM
    // interval and schedules the card a century out.
    c.stability = math.max(c.stability, 0.1);
    final r = _retrievability(elapsedDays, c.stability);
    // Both S' and D' are functions of the PRE-review state (py-fsrs v4
    // semantics); feeding the already-updated difficulty into the stability
    // formula systematically underestimates post-lapse stability.
    final oldD = c.difficulty;
    c.difficulty = _nextDifficulty(oldD, rating);
    if (rating == Rating.again) {
      c.stability = _nextForgetStability(oldD, c.stability, r);
    } else {
      c.stability = _nextRecallStability(oldD, c.stability, r, rating);
    }
  }

  double _initStability(Rating r) {
    final idx = r.index; // 0..3
    final s = w[idx];
    return math.max(s, 0.1);
  }

  double _initDifficulty(Rating r) {
    final g = ratingToInt(r).toDouble();
    return _clampDifficulty(w[4] - (g - 3) * w[5]);
  }

  double _clampDifficulty(double d) => d.clamp(1.0, 10.0);

  double _nextDifficulty(double d, Rating r) {
    final g = ratingToInt(r).toDouble();
    final newD = d - w[6] * (g - 3);
    // Mean reversion to w[4].
    final meanReverted = w[7] * w[4] + (1 - w[7]) * newD;
    return _clampDifficulty(meanReverted);
  }

  double _nextRecallStability(double d, double s, double r, Rating rating) {
    final hardPenalty = rating == Rating.hard ? w[15] : 1.0;
    final easyBonus = rating == Rating.easy ? w[16] : 1.0;
    final factor = math.exp(w[8]) *
        (11 - d) *
        math.pow(s, -w[9]) *
        (math.exp(w[10] * (1 - r)) - 1);
    return s * (1 + factor * hardPenalty * easyBonus);
  }

  double _nextForgetStability(double d, double s, double r) {
    final forgotten = w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1, w[13]) - 1) *
        math.exp(w[14] * (1 - r));
    // Forgetting must never lengthen the interval. Over the range real cards
    // occupy — short stabilities seeded at w[0] — the raw formula frequently
    // exceeds the current stability, so failing a review would push it
    // further away. The reference implementation clamps here too.
    return math.min(forgotten, s);
  }

  double _retrievability(double elapsedDays, double stability) {
    if (stability <= 0) return 0.0;
    return math.pow(1 + elapsedDays / (9 * stability), -1).toDouble();
  }

  double _nextInterval(double stability) {
    final interval =
        stability * 9 * (1 / requestRetention - 1);
    return interval.clamp(1.0, 36500.0);
  }
}
