import 'dart:math' as math;

/// Glicko-2 rating implementation following Glickman (2013).
/// Each call to [update] treats one puzzle attempt as a one-game rating period.
///
/// Public fields: [rating] (display rating), [rd] (rating deviation),
/// [volatility]. The internal μ, φ scale is used during updates only.
class Glicko2 {
  /// Seed rating for a new player. Below the Glicko paper's 1500, which is
  /// pitched too high for an undifferentiated puzzle pool: 1200 puts most
  /// new players in the 50-70% success range on their first puzzle, near
  /// the desirable-difficulty target.
  static const double _defaultRating = 1200.0;

  /// Also the ceiling on [rd]: nothing is less certain than an unrated player.
  static const double _defaultRd = 350.0;
  static const double _defaultVolatility = 0.06;
  static const double _tau = 0.5;
  static const double _scale = 173.7178; // (400 / ln(10)).
  static const double _convergence = 1e-6;

  /// Iteration caps for the volatility solve. Glickman's procedure converges
  /// in a handful of steps; these exist so a degenerate input degrades to a
  /// slightly-off volatility rather than an unkillable loop.
  static const int _maxBracketSteps = 100;
  static const int _maxSolverSteps = 100;

  double rating;
  double rd;
  double volatility;

  Glicko2({
    this.rating = _defaultRating,
    this.rd = _defaultRd,
    this.volatility = _defaultVolatility,
  });

  /// Glicko-2 internal mu.
  double get _mu => (rating - 1500.0) / _scale;
  /// Glicko-2 internal phi.
  double get _phi => rd / _scale;

  /// Apply a single game outcome against an opponent with the given rating
  /// and RD. [score] is 1 for win, 0 for loss, 0.5 for draw. [weight] in
  /// [0, 1] scales the update (used for secondary themes).
  void update({
    required double opponentRating,
    required double opponentRd,
    required double score,
    double weight = 1.0,
  }) {
    final muJ = (opponentRating - 1500.0) / _scale;
    final phiJ = opponentRd / _scale;

    // [weight] is a fractional game count, so it scales the INFORMATION the
    // attempt carries: the effective variance is v / weight. A zero-weight
    // attempt carries none and must leave rating, deviation and volatility
    // untouched, and a weight above one would fabricate information that
    // the single attempt does not contain.
    if (weight <= 0.0) return;
    weight = math.min(weight, 1.0);

    final g = _g(phiJ);
    // Clamped away from {0, 1}: at a rating gap of ~6400 the expectation
    // rounds to exactly 1.0 in doubles, which makes v infinite and delta
    // NaN, degrading the whole update to a no-op.
    final expected = _e(_mu, muJ, phiJ).clamp(1e-10, 1.0 - 1e-10);

    final v = 1.0 / (g * g * expected * (1.0 - expected));
    final vWeighted = v / weight;
    // Delta is weight-independent: vWeighted * (weight * g * (score -
    // expected)) collapses to v * g * (score - expected).
    final delta = v * g * (score - expected);

    // Step 5 — compute new volatility σ'.
    final a = math.log(volatility * volatility);
    final tau2 = _tau * _tau;

    double f(double x) {
      final ex = math.exp(x);
      final num1 = ex * (delta * delta - _phi * _phi - vWeighted - ex);
      final den1 = 2 * math.pow(_phi * _phi + vWeighted + ex, 2);
      return num1 / den1 - (x - a) / tau2;
    }

    double A = a;
    double B;
    if (delta * delta > _phi * _phi + vWeighted) {
      B = math.log(delta * delta - _phi * _phi - vWeighted);
    } else {
      // Bounded: f grows without limit as x falls, so the bracket is found
      // within a few steps for any well-formed input. An unbounded search
      // here turns a degenerate input into a spin that no timeout can
      // interrupt, because nothing yields to the event loop.
      int k = 1;
      while (k < _maxBracketSteps && f(a - k * _tau) < 0) {
        k += 1;
      }
      B = a - k * _tau;
    }

    double fA = f(A);
    double fB = f(B);
    // The Illinois iteration converges quickly; the cap only matters when a
    // non-finite value stalls it. Same reasoning as above — a numeric loop
    // in a rating update must not be able to hang the isolate.
    var steps = 0;
    while ((B - A).abs() > _convergence && steps < _maxSolverSteps) {
      steps += 1;
      final C = A + (A - B) * fA / (fB - fA);
      final fC = f(C);
      if (fC * fB <= 0) {
        A = B;
        fA = fB;
      } else {
        fA = fA / 2.0;
      }
      B = C;
      fB = fC;
    }
    final newVolatility = math.exp(A / 2.0);

    // Step 6 — update phi*.
    final phiStar = math.sqrt(_phi * _phi + newVolatility * newVolatility);

    // Step 7 — new phi, new mu. The deviation shrinks by the information
    // actually supplied (1 / vWeighted), so a half-weight attempt tightens
    // the rating half as much as a full one.
    final newPhi =
        1.0 / math.sqrt(1.0 / (phiStar * phiStar) + 1.0 / vWeighted);
    final newMu = _mu + newPhi * newPhi * g * (score - expected) * weight;

    rating = newMu * _scale + 1500.0;
    rd = math.min(newPhi * _scale, _defaultRd);
    volatility = newVolatility;
  }

  /// Apply an inactive rating period (no game), inflating the deviation by
  /// the volatility. The result is capped at [_defaultRd]: an unrated player
  /// is the most uncertain case there is, so no amount of inactivity may
  /// leave the estimate less certain than a brand-new one.
  void decay() {
    final newPhi = math.sqrt(_phi * _phi + volatility * volatility);
    rd = math.min(newPhi * _scale, _defaultRd);
  }

  double _g(double phi) {
    return 1.0 / math.sqrt(1.0 + 3.0 * phi * phi / (math.pi * math.pi));
  }

  double _e(double mu, double muJ, double phiJ) {
    return 1.0 / (1.0 + math.exp(-_g(phiJ) * (mu - muJ)));
  }

  @override
  String toString() =>
      'Glicko2(r=${rating.toStringAsFixed(1)}, rd=${rd.toStringAsFixed(1)}, '
      'vol=${volatility.toStringAsFixed(4)})';
}
