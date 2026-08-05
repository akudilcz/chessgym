import 'dart:math' as math;

/// Compute a [0,1] weakness score for a theme the player should practice.
///
/// Feeds the adaptive-practice sampler. The weights are documented in
/// `design/scoring.md`; recent performance dominates so the recommendation
/// reacts to a player's current form rather than their lifetime average.
double weaknessScore({
  required double mastery,
  required int attempts,
  required int solved,
  required double rd,
  double? recentFailRate, // rolling last-N-attempts fail rate; null if unknown
  double rdReference = 350.0,
  double coldStartBump = 0.2,
}) {
  final invMastery = (1.0 - mastery).clamp(0.0, 1.0);
  final failRate = attempts == 0
      ? 0.5
      : ((attempts - solved) / attempts).clamp(0.0, 1.0);
  final rdNorm = (rd / rdReference).clamp(0.0, 1.0);
  // Enters the sum through its 0.10 term weight, so the default 0.2 bump
  // contributes 0.02 to the final score (design/scoring.md documents the
  // formula this way; the untouched theme is mostly promoted by the 0.5
  // fail-rate prior and the maximal rdNorm term, not by this nudge).
  final coldStart = attempts == 0 ? coldStartBump : 0.0;
  // Recent performance dominates. A single missed puzzle moves the
  // rolling window fail rate by 1/window, so with 40% weight a fail
  // visibly bumps weakness by ~0.04 per attempt.
  final recent = recentFailRate ?? failRate;
  final w = 0.20 * invMastery +
      0.10 * failRate +
      0.40 * recent +
      0.20 * rdNorm +
      0.10 * coldStart;
  return w.clamp(0.0, 1.0);
}

/// Power-weighted sample: pick an index with probability proportional to
/// `weights[i]^alpha`, guaranteeing every item at least [floor] probability
/// so no item ever starves entirely. [floor] is per-item; when `n * floor`
/// would exceed the whole budget it degrades toward uniform sampling.
int sampleWithFloor(
  List<double> weights,
  math.Random rng, {
  double alpha = 2.5,
  double floor = 0.02,
}) {
  if (weights.isEmpty) {
    throw ArgumentError.value(weights, 'weights', 'must not be empty');
  }
  final n = weights.length;
  final raw =
      weights.map((w) => math.pow(w.clamp(0.0, 1.0), alpha).toDouble()).toList();
  final total = raw.fold<double>(0, (a, b) => a + b);
  final effFloor = math.min(floor, 1.0 / n);
  final dist = List<double>.generate(n, (i) {
    final normalized = total > 0 ? raw[i] / total : 1.0 / n;
    return effFloor + (1 - n * effFloor) * normalized;
  });
  final sum = dist.fold<double>(0, (a, b) => a + b);
  final t = rng.nextDouble() * sum;
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    acc += dist[i];
    if (acc >= t) return i;
  }
  return n - 1;
}
