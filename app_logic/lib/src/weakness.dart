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

/// Softmax-sample an index from [weights] raised to [alpha], with a per-
/// item probability [floor] so no item ever starves entirely.
int sampleWithFloor(
  List<double> weights,
  math.Random rng, {
  double alpha = 2.5,
  double floor = 0.02,
}) {
  assert(weights.isNotEmpty);
  final n = weights.length;
  final raw =
      weights.map((w) => math.pow(w.clamp(0.0, 1.0), alpha).toDouble()).toList();
  final total = raw.fold<double>(0, (a, b) => a + b);
  final dist = List<double>.generate(n, (i) {
    final normalized = total > 0 ? raw[i] / total : 1.0 / n;
    return floor / n + (1 - floor) * normalized;
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
