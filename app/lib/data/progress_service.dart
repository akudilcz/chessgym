import 'dart:math' as math;

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../domain/puzzle.dart';
import 'player_db.dart';
import 'puzzle_db.dart';

// Selection-policy constants — keep in sync with SelectionService.
// [_dueShare] is the fraction of the display probability weighted
// toward fading themes; the remainder flows through softmax over
// the full available pool.
const double _dueShare = 0.30;
const double _weaknessAlpha = 5.0;
const double _floorProbability = 0.02;

/// A snapshot of the player's journey across the theme constellation.
///
/// No themes are locked. Every theme is always tappable. `weakness` drives
/// which theme the next-step recommender prefers — themes the player has
/// less experience with, or performs worse in, score higher and surface
/// first in the "Keep practicing" queue.
class ThemeProgress {
  final ThemeInfo theme;
  final int total;
  final int solved;
  final int attempts;
  final double mastery;       // [0,1] rating-based
  final double weakness;      // [0,1] — 1 = should practice, 0 = mastered
  /// Current Glicko-2 rating deviation for this theme. Feeds the
  /// Thompson sampler as the exploration posterior width: high-RD
  /// themes (fresh / seldom-practised) get wider samples and thus
  /// more exploration.
  final double rd;
  final bool isNext;          // true for the single recommended "next step"
  /// Estimated probability the player would still solve a representative
  /// puzzle in this theme right now, based on an exponential-decay model
  /// fed by (solves_in_theme, days_since_last_practice). 1.0 = fresh;
  /// drops as time since last solve passes. Null when the theme has no
  /// history (cold start).
  final double? retrievability;
  /// Days since the player's most recent attempt in this theme, or null
  /// if they've never tried it.
  final double? daysSincePractice;
  /// True when retrievability has dipped below the target (0.85) — the
  /// theme is fading and should be re-drilled.
  final bool fading;
  /// Probability [0,1] this theme is the one served on the next PLAY tap,
  /// given the current selection policy (priority share + weakness softmax
  /// + per-theme floor, excluding fully-cleared themes). Does NOT include
  /// the 5% missed-revisit or 20% FSRS-review slots — those are orthogonal.
  final double selectionProbability;

  const ThemeProgress({
    required this.theme,
    required this.total,
    required this.solved,
    required this.attempts,
    required this.mastery,
    required this.weakness,
    required this.rd,
    required this.isNext,
    required this.selectionProbability,
    required this.retrievability,
    required this.daysSincePractice,
    required this.fading,
  });

  int get failed => attempts - solved;
  double? get successRate => attempts == 0 ? null : solved / attempts;
}

class JourneySnapshot {
  final List<ThemeProgress> themes;
  final Glicko2 globalRating;
  final int totalSolved;
  final int totalAttempts;

  /// Distinct puzzles ever attempted — the clear-rate denominator.
  final int distinctSeen;

  /// Puzzles whose MOST RECENT outcome was 'failed' — i.e. the player
  /// hasn't yet cleared them. Goal of the app: drive this to zero.
  final int missedCount;

  /// Cumulative XP — kept simple: 1 per solve attempt + bonus for rating delta.
  /// Always monotone-non-decreasing so a level-up signal is always possible.
  final int xp;

  /// Player level from XP (arbitrary curve; see [levelFromXp]).
  final int level;

  /// XP at start of current level / at start of next level (for progress bar).
  final int xpAtLevel;
  final int xpAtNextLevel;

  /// Single theme to practice next, if any themes are tracked.
  final ThemeProgress? recommendedNext;

  const JourneySnapshot({
    required this.themes,
    required this.globalRating,
    required this.totalSolved,
    required this.totalAttempts,
    this.distinctSeen = 0,
    required this.missedCount,
    required this.xp,
    required this.level,
    required this.xpAtLevel,
    required this.xpAtNextLevel,
    required this.recommendedNext,
  });
}

/// Cumulative XP → level.
/// Quadratic curve: level L starts at XP = 5 * L * (L+1). So:
///   level 1 → 10 XP,  level 2 → 30 XP,  level 3 → 60 XP,  ...
/// Every attempt grants at least +1 XP, so level always eventually goes up.
int levelFromXp(int xp) {
  // Solve 5L(L+1) <= xp  →  L = floor((-1 + sqrt(1 + 4*xp/5)) / 2).
  if (xp < 10) return 0;
  return ((math.sqrt(1 + (xp / 5.0) * 4) - 1) / 2).floor();
}

int xpFloorForLevel(int level) => 5 * level * (level + 1);

class ProgressService {
  final PuzzleDb puzzles;
  final PlayerDb player;

  ProgressService(this.puzzles, this.player);

  Future<JourneySnapshot> snapshot() async {
    final swTotal = Stopwatch()..start();
    final profile = <String, int>{};
    Future<T> step<T>(String label, Future<T> Function() fn) async {
      final sw = Stopwatch()..start();
      final v = await fn();
      profile[label] = sw.elapsedMilliseconds;
      return v;
    }

    // Puzzle-side reads are all cached at PuzzleDb level — first call
    // pays the cost (~700 ms on phone), subsequent snapshots hit memory.
    final themes = await step('listThemes', puzzles.listThemes);
    final totals = await step('themeTotals', puzzles.themeTotals);
    final puzzleThemes =
        await step('puzzleThemesMap', puzzles.puzzleThemesMap);

    // Tiny attempts scan + Dart-side aggregation via the cached map.
    // Warm-path: ~1–5 ms.
    final agg = await step(
        'aggregateAttempts',
        () => player.aggregateAttempts(
              puzzleThemes,
              recentWindowPerTheme: 10,
            ));
    final solved = agg.solvedByTheme;
    final attempts = agg.attemptedByTheme;
    final recentFails = agg.recentFailRateByTheme;
    final lastAttemptPerTheme = agg.lastAttemptPerTheme;

    final global = await step('globalRating', player.globalRating);
    final totalSolved = await step('totalSolved', player.totalSolvedCount);
    final totalAttempts =
        await step('totalAttempts', player.totalAttemptsCount);
    final distinctSeen =
        await step('distinctSeen', player.distinctSeenCount);
    final missed = await step('missedCount', player.missedCount);
    final nowTs = DateTime.now();

    // Per-theme ratings — one round-trip, not N.
    final ratingsByTheme =
        await step('allThemeRatings', player.allThemeRatings);
    final ratings = <String, Glicko2>{
      for (final t in themes) t.id: ratingsByTheme[t.id] ?? Glicko2(),
    };

    // Compute per-theme weakness first; needed to derive selection
    // probabilities in one pass.
    final pre = <Map<String, dynamic>>[];
    for (final t in themes) {
      final r = ratings[t.id] ?? Glicko2();
      final m = mastery(
        playerRating: r.rating,
        floorRating: t.floorRating,
        ceilingRating: t.ceilingRating,
      );
      final a = attempts[t.id] ?? 0;
      final s = solved[t.id] ?? 0;
      final total = totals[t.id] ?? 0;
      final w = weaknessScore(
        mastery: m,
        attempts: a,
        solved: s,
        rd: r.rd,
        recentFailRate: recentFails[t.id],
      );
      // "Depth" = how many fresh (unsolved) puzzles the theme has.
      // Selection weights scale with depth so a theme with 3 puzzles can
      // never hog the queue regardless of weakness.
      final depth = (total - s).clamp(0, 10000);
      final depthFactor =
          (depth / 10).clamp(0.0, 1.0); // 1.0 at ≥ 10 fresh puzzles

      // Theme-level forgetting model. Exponential decay: R(t) = exp(-t/S).
      // S (stability days) grows with successful solves: each solve doubles
      // retention up to a cap. Failures keep S at a low floor.
      // This mirrors FSRS at the category level — the player sees a theme
      // again just before their competency fades.
      final last = lastAttemptPerTheme[t.id];
      final daysSince = last == null
          ? null
          : nowTs.difference(last).inSeconds / 86400.0;
      double? retrievability;
      bool fading = false;
      if (daysSince != null) {
        // Stability: 1 day at zero solves, doubling per solve up to ~64 days.
        final stability = math.min(64.0, math.pow(2, s).toDouble());
        retrievability = math.exp(-daysSince / stability);
        fading = retrievability < 0.85;
      }
      // Forgetting boost: a faded theme's weakness gets bumped so
      // selection surfaces it. Max boost 0.25 when retrievability → 0.
      final forgettingBoost =
          retrievability == null ? 0.0 : math.max(0.0, 0.85 - retrievability);
      final weaknessBoosted = (w + 0.3 * forgettingBoost).clamp(0.0, 1.0);

      pre.add({
        'theme': t,
        'total': total,
        'solved': s,
        'attempts': a,
        'mastery': m,
        'weakness': weaknessBoosted,
        'rd': r.rd,
        'available': total == 0 || s < total,
        'depthFactor': depthFactor,
        'retrievability': retrievability,
        'daysSince': daysSince,
        'fading': fading,
      });
    }

    // Selection probability (UI display only): closed-form softmax
    // over weakness with a per-theme floor, mixed with a DUE-NOW bucket.
    //
    // The old implementation ran 2000-trial Monte Carlo here to
    // approximate the Thompson-sampling argmax distribution. That cost
    // 1.35M Box-Muller samples on the UI isolate every time the
    // dashboard refreshed — pure overhead, since the user only ever
    // sees a rounded percentage. Closed-form softmax is a couple of
    // microseconds and matches Thompson's ordering almost exactly
    // (both favour high-weakness themes monotonically).
    final anyAvailable = pre.any((x) => x['available'] as bool);
    final poolIdxs = [
      for (var i = 0; i < pre.length; i++)
        if (anyAvailable ? pre[i]['available'] as bool : true) i
    ];
    final dueIdxs = [
      for (final i in poolIdxs) if (pre[i]['fading'] == true) i
    ];

    List<double> softmaxOver(List<int> idxs) {
      if (idxs.isEmpty) return const [];
      // Numeric-stable softmax: subtract max before exp.
      double maxW = -double.infinity;
      for (final i in idxs) {
        final w = pre[i]['weakness'] as double;
        if (w > maxW) maxW = w;
      }
      final exps = [
        for (final i in idxs)
          math.exp(_weaknessAlpha * ((pre[i]['weakness'] as double) - maxW))
      ];
      final sum = exps.fold<double>(0, (a, b) => a + b);
      final raw = [for (final e in exps) e / sum];
      // Per-theme probability floor. Renormalise after flooring.
      final floored = [
        for (final p in raw) math.max(p, _floorProbability)
      ];
      final s = floored.fold<double>(0, (a, b) => a + b);
      return [for (final p in floored) p / s];
    }

    final poolProb = softmaxOver(poolIdxs);
    final dueProb = softmaxOver(dueIdxs);

    final probs = List<double>.filled(pre.length, 0.0);
    final dueWeight = dueIdxs.isEmpty ? 0.0 : _dueShare;
    final poolWeight = 1.0 - dueWeight;
    for (var k = 0; k < poolIdxs.length; k++) {
      probs[poolIdxs[k]] += poolWeight * poolProb[k];
    }
    for (var k = 0; k < dueIdxs.length; k++) {
      probs[dueIdxs[k]] += dueWeight * dueProb[k];
    }

    final progresses = <ThemeProgress>[];
    for (var i = 0; i < pre.length; i++) {
      final row = pre[i];
      progresses.add(ThemeProgress(
        theme: row['theme'] as ThemeInfo,
        total: row['total'] as int,
        solved: row['solved'] as int,
        attempts: row['attempts'] as int,
        mastery: row['mastery'] as double,
        weakness: row['weakness'] as double,
        rd: row['rd'] as double,
        isNext: false,
        selectionProbability: probs[i],
        retrievability: row['retrievability'] as double?,
        daysSincePractice: row['daysSince'] as double?,
        fading: row['fading'] as bool,
      ));
    }

    // Display order: by selection probability (highest first) — the theme
    // at the top of the FOCUS list is, by construction, the most likely
    // next puzzle. Ties broken by theme importance then id.
    progresses.sort((a, b) {
      final p = b.selectionProbability.compareTo(a.selectionProbability);
      if (p != 0) return p;
      final imp = b.theme.importance.compareTo(a.theme.importance);
      if (imp != 0) return imp;
      return a.theme.id.compareTo(b.theme.id);
    });
    final recommended = progresses.isEmpty ? null : progresses.first;

    final xp = _xpFromHistory(
      totalAttempts: totalAttempts,
      totalSolved: totalSolved,
    );
    final level = levelFromXp(xp);

    if (kDebugMode) {
      final top = profile.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[SNAPSHOT] total=${swTotal.elapsedMilliseconds}ms '
          '${top.take(6).map((e) => '${e.key}=${e.value}ms').join(' ')}');
    }

    return JourneySnapshot(
      themes: progresses,
      globalRating: global,
      totalSolved: totalSolved,
      totalAttempts: totalAttempts,
      distinctSeen: distinctSeen,
      missedCount: missed,
      xp: xp,
      level: level,
      xpAtLevel: xpFloorForLevel(level),
      xpAtNextLevel: xpFloorForLevel(level + 1),
      recommendedNext: recommended,
    );
  }

  int _xpFromHistory({
    required int totalAttempts,
    required int totalSolved,
  }) {
    // 1 XP per attempt (always climbs), +5 XP per solve (reward success).
    // This guarantees the XP bar moves forward whenever the user plays,
    // regardless of whether they solve.
    return totalAttempts + 5 * totalSolved;
  }
}
