import 'dart:math' as math;

/// Minimal puzzle candidate type for selection.
class PuzzleCandidate {
  final String id;
  final int rating;
  final double interest;
  final List<String> themes;
  final DateTime? lastSeen;
  final bool alreadySolved;

  const PuzzleCandidate({
    required this.id,
    required this.rating,
    required this.interest,
    required this.themes,
    this.lastSeen,
    this.alreadySolved = false,
  });
}

class SelectionParams {
  final int bandBelow;
  final int bandAbove;
  final int maxBandWiden;
  final int widenStep;
  final int recencyWindowDays;
  final int minCandidates;

  /// Puzzles seen within this many hours count as "recently seen" and are
  /// hard-excluded when there are fresher alternatives in the candidate set.
  final int recencyExcludeHours;

  const SelectionParams({
    // Band is biased upward — we want puzzles slightly harder than the
    // player's current rating (the 75-85 % success zone per Bjork's
    // desirable-difficulty principle), not balanced 50/50.
    this.bandBelow = 0,
    this.bandAbove = 300,
    this.maxBandWiden = 500,
    this.widenStep = 50,
    this.recencyWindowDays = 90,
    this.minCandidates = 20,
    this.recencyExcludeHours = 72,
  });
}

/// Selects the next puzzle.
///
/// Within the rating band, the pool is tiered:
///   Tier 1: never-seen, never-solved — always preferred.
///   Tier 2: seen but not in the last [recencyExcludeHours], not yet solved.
///   Tier 3: recently seen but not solved.
///   Tier 4: already solved (allow, last resort — e.g. review or tiny pool).
///
/// The highest non-empty tier is the pool; within that pool, weight by
/// interest² × recencyDecay and sample. Previously everything was one pool
/// with a 20×-at-most down-weight, which made a just-solved puzzle
/// re-appear the very next turn when the theme had few candidates.
class Selection {
  final SelectionParams params;
  final math.Random rng;

  Selection({
    this.params = const SelectionParams(),
    math.Random? rng,
  }) : rng = rng ?? math.Random();

  PuzzleCandidate? pickNext({
    required List<PuzzleCandidate> candidates,
    required int playerRating,
    required DateTime now,
  }) {
    if (candidates.isEmpty) return null;

    // Asymmetric band: widen ABOVE the player's rating, never below.
    // Serving below-rating puzzles triggers Glicko's 'expected win'
    // asymmetry (small wins, big losses), which felt unfair to players.
    // The only exception: if we absolutely cannot find candidates after
    // widening all the way up, fall back to the full set.
    int below = params.bandBelow;
    int above = params.bandAbove;
    List<PuzzleCandidate> band = [];
    while (true) {
      band = candidates.where((p) {
        return p.rating >= playerRating - below &&
            p.rating <= playerRating + above;
      }).toList();
      if (band.length >= params.minCandidates) break;
      // [maxBandWiden] is a band WIDTH, like [above] — not an absolute
      // rating. Comparing it against `playerRating + maxBandWiden` would
      // widen the band to roughly the player's whole rating range.
      if (above >= params.maxBandWiden) {
        if (band.isEmpty) band = List.of(candidates);
        break;
      }
      // Widen UPWARD only. `below` stays pinned at params.bandBelow (0).
      above += params.widenStep;
    }
    if (band.isEmpty) return null;

    final recencyCutoff = now.subtract(
      Duration(hours: params.recencyExcludeHours),
    );

    // Partition into tiers.
    final t1 = <PuzzleCandidate>[]; // never seen, not solved
    final t2 = <PuzzleCandidate>[]; // seen long ago, not solved
    final t3 = <PuzzleCandidate>[]; // recently seen, not solved
    final t4 = <PuzzleCandidate>[]; // already solved
    for (final p in band) {
      if (p.alreadySolved) {
        t4.add(p);
      } else if (p.lastSeen == null) {
        t1.add(p);
      } else if (p.lastSeen!.isBefore(recencyCutoff)) {
        t2.add(p);
      } else {
        t3.add(p);
      }
    }

    // Highest non-empty tier becomes the pool.
    final pool = t1.isNotEmpty
        ? t1
        : t2.isNotEmpty
            ? t2
            : t3.isNotEmpty
                ? t3
                : t4;
    if (pool.isEmpty) return null;

    final weights = pool.map((p) {
      final base = math.pow(p.interest.clamp(0.0, 1.0), 2).toDouble();
      final recencyDecay = _recencyDecay(p.lastSeen, now);
      return math.max(base * recencyDecay, 1e-9);
    }).toList();

    return _weightedPick(pool, weights);
  }

  double _recencyDecay(DateTime? lastSeen, DateTime now) {
    if (lastSeen == null) return 1.0;
    final days = now.difference(lastSeen).inHours / 24.0;
    if (days >= params.recencyWindowDays) return 1.0;
    return 0.05 + 0.95 * (days / params.recencyWindowDays);
  }

  PuzzleCandidate _weightedPick(
    List<PuzzleCandidate> items,
    List<double> weights,
  ) {
    final total = weights.fold<double>(0.0, (a, b) => a + b);
    final target = rng.nextDouble() * total;
    double cum = 0.0;
    for (int i = 0; i < items.length; i++) {
      cum += weights[i];
      if (cum >= target) return items[i];
    }
    return items.last;
  }
}
