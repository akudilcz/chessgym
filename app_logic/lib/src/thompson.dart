import 'dart:math' as math;

/// Thompson sampling for per-theme practice selection.
///
/// Given a list of themes with (weakness, uncertainty) pairs, sample
/// from each theme's posterior and return the index of the maximum.
/// This inherently favors high-weakness themes while still giving
/// high-uncertainty themes genuine variety — back-to-back duplicates
/// are rare without needing an explicit anti-cluster rule.
///
/// [weakness] — point estimate in [0,1].
/// [uncertainty] — standard deviation of the posterior, in [0,1].
///   Theme-ratings with high Glicko RD map to high uncertainty.
/// [rng] — injected so tests are deterministic.
int thompsonPick({
  required List<double> weakness,
  required List<double> uncertainty,
  required math.Random rng,
}) {
  // Thrown (not asserted): in release mode an empty list would silently
  // return index 0 and a length mismatch would RangeError mid-loop.
  if (weakness.isEmpty) {
    throw ArgumentError.value(weakness, 'weakness', 'must not be empty');
  }
  if (weakness.length != uncertainty.length) {
    throw ArgumentError(
        'weakness (${weakness.length}) and uncertainty '
        '(${uncertainty.length}) must have the same length');
  }
  var bestIdx = 0;
  var bestSample = -double.infinity;
  for (var i = 0; i < weakness.length; i++) {
    final sample = _sampleNormal(weakness[i], uncertainty[i], rng);
    if (sample > bestSample) {
      bestSample = sample;
      bestIdx = i;
    }
  }
  return bestIdx;
}

/// Box-Muller normal sample.
double _sampleNormal(double mean, double sd, math.Random rng) {
  if (sd <= 0) return mean;
  final u1 = math.max(rng.nextDouble(), 1e-12);
  final u2 = rng.nextDouble();
  final z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  return mean + sd * z;
}
