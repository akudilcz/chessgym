import 'dart:math' as math;

// ignore: unused_import
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

import '../domain/puzzle.dart';
import 'player_db.dart';
import 'progress_service.dart';
import 'puzzle_db.dart';

/// Picks the next puzzle.
///
/// Policy (no-lock variant):
///
///   With probability [reviewMissedRate] (default 5%), if the player has any
///   puzzles they've missed and not yet re-solved, serve one to drive the
///   "eventually 100% cleared" goal. The other 95% of the time, explore:
///
///     1. If the caller passed [themeFocus], restrict to that theme.
///     2. Otherwise, sample a theme by weakness^alpha (softmax with
///        probability floor). See design/scoring.md.
///     3. Within the theme, pick a puzzle in the player's rating band,
///        preferring never-seen puzzles, weighted by interest^2 * recency.
///
/// FSRS due-reviews layer on top of the 5% missed-revisit slot — they use
/// the same pool so we don't double-book.
class SelectionService {
  final PuzzleDb puzzles;
  final PlayerDb player;
  final ProgressService progress;
  final Selection _selection;
  final math.Random _rng;

  /// Softmax concentration over weakness. Higher = steeper skew toward
  /// weak themes. With 28+ themes on the board, values below ~4 spread
  /// probability too thin — the "PRIORITY" theme was getting <10% before
  /// alpha was raised.
  final double weaknessAlpha;

  /// Per-theme probability floor.
  final double floorProbability;

  /// The single "PRIORITY" theme (highest weakness) gets a guaranteed slice
  /// of selection probability. Everything else competes for the remainder
  /// via softmax. Default 0.45 — roughly every other puzzle comes from
  /// the theme the dashboard is telling the player to focus on, which
  /// matches user expectation of what "PRIORITY" means.
  final double priorityShare;

  /// Fraction of puzzles that should be revisits of previously-missed
  /// (and not-yet-cleared) puzzles. Default 5%.
  final double reviewMissedRate;

  SelectionService(
    this.puzzles,
    this.player, {
    math.Random? rng,
    this.weaknessAlpha = 5.0,
    this.floorProbability = 0.02,
    this.priorityShare = 0.45,
    this.reviewMissedRate = 0.05,
  })  : _rng = rng ?? math.Random(),
        progress = ProgressService(puzzles, player),
        _selection = Selection(rng: rng);

  /// Pick the next puzzle.
  ///
  /// Callers that already have a [JourneySnapshot] (e.g. the dashboard
  /// provider) should pass it in to avoid recomputing the 12-query,
  /// 2000-trial Monte-Carlo snapshot a second time on every puzzle
  /// transition — that double-compute was the source of multi-second
  /// UI locks on Android.
  Future<Puzzle?> pickNext({
    required String? themeFocus,
    required DateTime now,
    JourneySnapshot? snapshot,
  }) async {
    final swTotal = Stopwatch()..start();
    final profile = <String, int>{};
    Future<T> step<T>(String label, Future<T> Function() fn) async {
      final sw = Stopwatch()..start();
      final v = await fn();
      profile[label] = sw.elapsedMilliseconds;
      return v;
    }
    final out = await _pickNextInner(
      themeFocus: themeFocus,
      now: now,
      snapshot: snapshot,
      step: step,
    );
    final top = profile.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print('[PICK] total=${swTotal.elapsedMilliseconds}ms '
        '${top.take(6).map((e) => '${e.key}=${e.value}ms').join(' ')}');
    return out;
  }

  Future<Puzzle?> _pickNextInner({
    required String? themeFocus,
    required DateTime now,
    required JourneySnapshot? snapshot,
    required Future<T> Function<T>(String, Future<T> Function()) step,
  }) async {
    // CALIBRATION short-circuit: during the first 5 puzzles, ignore Glicko
    // and weakness entirely — just serve a puzzle at the calibration
    // target rating. Binary search over levels lets us peg the player in
    // 5 attempts instead of 15-20.
    if (themeFocus == null) {
      final (done, _, target) = await step('calibrationState', player.calibrationState);
      if (!done) {
        final p = await step('puzzleNearRating',
            () => puzzles.puzzleNearRating(target.round()));
        if (p != null) return p;
      }
    }

    // Revisit roll: with probability reviewMissedRate, pick a missed puzzle.
    // Only when the caller didn't specify a theme focus (user-initiated "just
    // give me whatever I need") — theme-locked selection always respects the
    // caller's intent.
    if (themeFocus == null && _rng.nextDouble() < reviewMissedRate) {
      final missed = await step('missedPuzzleIds', player.missedPuzzleIds);
      if (missed.isNotEmpty) {
        final id = missed[_rng.nextInt(missed.length)];
        final puz = await step('byId', () => puzzles.byId(id));
        if (puz != null) return puz;
      }
    }

    // Optional FSRS review queue — already due puzzles get served before
    // random missed ones when their clock fires.
    final reviews = await step('loadReviewQueue', player.loadReviewQueue);
    final due = reviews.entries
        .where((e) => e.value.due != null && !e.value.due!.isAfter(now))
        .toList()
      ..sort((a, b) => a.value.due!.compareTo(b.value.due!));
    if (due.isNotEmpty && themeFocus == null) {
      // Serve due reviews ahead of new puzzles only some of the time — we
      // don't want an all-review session ever.
      if (_rng.nextDouble() < 0.2) {
        final pzl = await puzzles.byId(due.first.key);
        if (pzl != null) return pzl;
      }
    }

    // Pick a theme via THOMPSON SAMPLING over per-theme weakness posteriors.
    //
    // Each theme has a point-estimate weakness and a Glicko-RD-derived
    // uncertainty. We draw one sample from each theme's distribution and
    // pick the theme with the highest sample. This naturally:
    //   - favors weak themes (they tend to sample high)
    //   - injects variety (stochastic — the same theme rarely wins twice
    //     in a row unless it's genuinely dominant)
    //   - handles exploration via uncertainty (high-RD themes sometimes
    //     win despite lower mean weakness)
    //
    // DUE-NOW is still a hard roll at 30% — spaced repetition is a
    // separate concern that should not be subsumed by weakness sampling.
    final String theme;
    if (themeFocus != null) {
      theme = themeFocus;
    } else {
      final snap = snapshot ?? await progress.snapshot();
      if (snap.themes.isEmpty) return null;
      final available = snap.themes
          .where((t) => t.total == 0 || t.solved < t.total)
          .toList();
      final pool = available.isEmpty ? snap.themes : available;

      final due = pool.where((t) => t.fading).toList();
      if (_rng.nextDouble() < 0.30 && due.isNotEmpty) {
        // Thompson over fading themes only.
        theme = _thompsonOver(due);
      } else {
        theme = _thompsonOver(pool);
      }
    }

    // Pick a puzzle within the theme, preferring ones the player hasn't seen.
    // Band is biased above the player's rating — aiming at the ~75-85%
    // challenge zone rather than 50/50. Early in a player's career
    // (RD high) we widen the band upward so the rating catches up to
    // true ability fast.
    final rating = await step('themeRating', () => player.themeRating(theme));
    final target = rating.rating.round();
    List<Puzzle> candidates = await step(
        'candidatesForTheme', () => _candidatesWithWidening(theme, target));
    if (candidates.isEmpty) {
      candidates = await step('fallbackAnyTheme', () => _fallbackAnyTheme(target));
    }
    if (candidates.isEmpty) {
      final any = await step('anyPuzzle', puzzles.anyPuzzle);
      if (any != null) return any;
      return null;
    }

    final seen = await step('seenRecency', player.seenRecency);
    final solved = await step('solvedPuzzleIds', player.solvedPuzzleIds);
    final list = candidates.map((p) {
      return PuzzleCandidate(
        id: p.id,
        rating: p.rating,
        interest: p.interest,
        themes: p.themes,
        lastSeen: seen[p.id],
        alreadySolved: solved.contains(p.id),
      );
    }).toList();

    final pick = _selection.pickNext(
      candidates: list,
      playerRating: target,
      now: now,
    );
    if (pick == null) return null;
    // candidatesForTheme returns puzzles with empty themes (perf); the UI
    // needs the theme list, so reload the picked puzzle by id.
    return await step('reloadPick', () => puzzles.byId(pick.id)) ??
        candidates.firstWhere((p) => p.id == pick.id);
  }

  /// Try the theme at increasingly wide rating bands, STRICTLY above the
  /// player's target rating. Serving below-rating puzzles gave Glicko
  /// asymmetric updates (expected wins give tiny gains, unexpected
  /// losses give big losses) — felt unfair and was the underlying
  /// cause of the +2 / -15 complaint.
  Future<List<Puzzle>> _candidatesWithWidening(String theme, int target) async {
    for (final high in [350, 600, 900, 1500]) {
      final c = await puzzles.candidatesForTheme(
        theme,
        ratingMin: target,           // never below player rating
        ratingMax: target + high,
        limit: 200,
      );
      if (c.isNotEmpty) return c;
    }
    // Final fallback: accept anything ≥ target − 100 (just in case a
    // theme truly has no puzzles at or above the player's level).
    final c = await puzzles.candidatesForTheme(
      theme,
      ratingMin: target - 100,
      ratingMax: target + 2400,
      limit: 200,
    );
    return c;
  }

  /// Last-resort: pick any puzzle near the player's rating, ignoring theme.
  /// Used when the chosen theme somehow returns zero candidates.
  Future<List<Puzzle>> _fallbackAnyTheme(int target) async {
    // Pull a few high-interest puzzles across the full corpus at any rating.
    final all = await puzzles.listThemes();
    for (final t in all) {
      final c = await puzzles.candidatesForTheme(
        t.id,
        ratingMin: 0,
        ratingMax: 9999,
        limit: 100,
      );
      if (c.isNotEmpty) return c;
    }
    return const [];
  }

  /// Thompson sampling over a theme list.
  ///
  /// Uncertainty is derived directly from the theme's Glicko-2 RD:
  /// fresh themes (RD ~ 350) get the widest posterior, converged themes
  /// (RD ~ 60) get the tightest.
  ///
  /// A 0.15 floor is kept so even fully-converged themes can occasionally
  /// steal a turn; otherwise argmax would lock onto the single weakest
  /// theme for long runs.
  String _thompsonOver(List<ThemeProgress> themes) {
    final weakness = themes.map((t) => t.weakness).toList();
    final uncertainty = themes.map((t) {
      const rdFloor = 60.0;     // Glicko-2 converged RD
      const rdCeiling = 350.0;  // Glicko-2 cold-start RD
      final norm =
          ((t.rd - rdFloor) / (rdCeiling - rdFloor)).clamp(0.0, 1.0);
      // 0.15 + 0.40 * norm keeps the band ≈ [0.15, 0.55] so behaviour
      // stays in the ballpark of the previous 0.20/0.40 fixed settings.
      return 0.15 + 0.40 * norm;
    }).toList();
    final idx = thompsonPick(
      weakness: weakness,
      uncertainty: uncertainty,
      rng: _rng,
    );
    return themes[idx].theme.id;
  }
}
