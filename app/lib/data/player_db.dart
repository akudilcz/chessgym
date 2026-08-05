import 'dart:io';

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Five-step binary search that pegs a new player's rating without
/// relying on Glicko's gradual convergence.
///
///   Step 0 → serve at 1200 (median)
///   After pass: next = current + 300
///   After fail: next = current - 300
///   Step 1 → step 300
///   Step 2 → step 200
///   Step 3 → step 100
///   Step 4 → step 50
///   After step 4, calibration_done = true and rating is set to the
///   last target. RD is compressed to 120 so subsequent Glicko updates
///   are small (we're confident in the calibrated level).
class Calibration {
  static const steps = 5;
  static const initialTarget = 1200.0;

  /// Step sizes (applied AFTER the attempt at each step). The last step's
  /// target just becomes the final rating.
  static const stepSizes = <double>[300, 300, 200, 100, 50];

  /// Given current step and outcome, return the NEXT target.
  static double nextTarget({
    required double currentTarget,
    required int step,
    required bool solved,
  }) {
    final size = stepSizes[step.clamp(0, stepSizes.length - 1)];
    return solved ? currentTarget + size : currentTarget - size;
  }
}

class PuzzleStats {
  final int attempts;
  final int solves;
  final int fails;
  final double? avgDurationMs;
  final int samplesUsed;
  const PuzzleStats({
    required this.attempts,
    required this.solves,
    required this.fails,
    required this.avgDurationMs,
    required this.samplesUsed,
  });
  double? get successRate => attempts == 0 ? null : solves / attempts;
}

class PlayerState {
  final Glicko2 global;
  final Map<String, Glicko2> byTheme;
  final Map<String, FsrsCard> reviewQueue;

  PlayerState({
    required this.global,
    required this.byTheme,
    required this.reviewQueue,
  });
}

class PlayerDb {
  static const _schema = '''
CREATE TABLE IF NOT EXISTS player (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  rating REAL NOT NULL, rd REAL NOT NULL, vol REAL NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  board_flipped_default INTEGER NOT NULL DEFAULT 0,
  sound_on INTEGER NOT NULL DEFAULT 1,
  high_contrast INTEGER NOT NULL DEFAULT 0,
  piece_set TEXT NOT NULL DEFAULT 'cburnett',
  reduced_motion INTEGER NOT NULL DEFAULT 0,
  calibration_done INTEGER NOT NULL DEFAULT 0,
  calibration_step INTEGER NOT NULL DEFAULT 0,
  calibration_target REAL NOT NULL DEFAULT 1200.0
);
CREATE TABLE IF NOT EXISTS theme_rating (
  theme_id TEXT PRIMARY KEY,
  rating REAL NOT NULL, rd REAL NOT NULL, vol REAL NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS attempts (
  puzzle_id TEXT NOT NULL, resolved_at TEXT NOT NULL,
  outcome TEXT NOT NULL, first_wrong_move_uci TEXT,
  rating_delta_global REAL NOT NULL,
  solve_duration_ms INTEGER,
  PRIMARY KEY (puzzle_id, resolved_at)
);
CREATE TABLE IF NOT EXISTS review_queue (
  puzzle_id TEXT PRIMARY KEY,
  stability REAL NOT NULL, difficulty REAL NOT NULL,
  due_at TEXT NOT NULL, last_review TEXT NOT NULL,
  last_rating INTEGER NOT NULL,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS seen_recency (
  puzzle_id TEXT PRIMARY KEY, last_seen TEXT NOT NULL
);
''';

  final Database _db;
  PlayerDb._(this._db);

  /// [playerDbPath] overrides the on-device location of `player.sqlite`.
  /// Tests pass a temp path so the schema, the idempotent migrations and the
  /// inactivity decay below all run for real, rather than being re-declared
  /// (and silently allowed to drift) inside a test file.
  static Future<PlayerDb> open({
    @visibleForTesting String? playerDbPath,
  }) async {
    final path = playerDbPath ??
        p.join((await getApplicationSupportDirectory()).path, 'player.sqlite');
    final db = await databaseFactory.openDatabase(path);
    for (final stmt in _schema.split(';')) {
      final s = stmt.trim();
      if (s.isNotEmpty) await db.execute(s);
    }
    // Migration: add solve_duration_ms column if missing (idempotent).
    final cols = await db.rawQuery('PRAGMA table_info(attempts)');
    if (!cols.any((c) => c['name'] == 'solve_duration_ms')) {
      await db.execute(
          'ALTER TABLE attempts ADD COLUMN solve_duration_ms INTEGER');
    }
    // Migration: FSRS counters on review_queue (idempotent). Without them a
    // rehydrated card was indistinguishable from a new one.
    final rcols = await db.rawQuery('PRAGMA table_info(review_queue)');
    for (final col in const ['reps', 'lapses']) {
      if (!rcols.any((c) => c['name'] == col)) {
        await db.execute(
            'ALTER TABLE review_queue ADD COLUMN $col INTEGER NOT NULL DEFAULT 0');
      }
    }
    // Migration: calibration columns on player table.
    final pcols = await db.rawQuery('PRAGMA table_info(player)');
    final addingCalibration =
        !pcols.any((c) => c['name'] == 'calibration_done');
    for (final col in const [
      ('calibration_done', 'INTEGER NOT NULL DEFAULT 0'),
      ('calibration_step', 'INTEGER NOT NULL DEFAULT 0'),
      ('calibration_target', 'REAL NOT NULL DEFAULT 1200.0'),
    ]) {
      if (!pcols.any((c) => c['name'] == col.$1)) {
        await db.execute('ALTER TABLE player ADD COLUMN ${col.$1} ${col.$2}');
      }
    }
    if (addingCalibration) {
      // A player row that already exists at the moment this column is added
      // predates calibration: their rating was earned from real solves.
      // Leaving them on the DEFAULT 0 re-runs calibration, and completing it
      // overwrites that rating, resets rd to 120 and DELETEs every per-theme
      // rating. Fresh installs seed their player row below, after this
      // statement, so they still calibrate.
      await db.update('player', {'calibration_done': 1}, where: 'id = 1');
    }
    // Seed the player row if missing.
    final rows = await db.rawQuery(
        'SELECT id, updated_at FROM player WHERE id = 1');
    if (rows.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('player', {
        'id': 1,
        'rating': 1200.0, 'rd': 350.0, 'vol': 0.06,
        'created_at': now, 'updated_at': now,
      });
    } else {
      // Glicko-2 inactivity decay: RD drifts upward slowly when the player
      // hasn't played in a while, so a long-absent player's rating doesn't
      // stay artificially confident. One period = ~7 days (Glickman's
      // suggested cadence for a casual/ad-hoc context).
      final updated =
          DateTime.tryParse(rows.first['updated_at'] as String);
      if (updated != null) {
        final days =
            DateTime.now().toUtc().difference(updated).inDays;
        final periods = (days / 7).floor();
        if (periods > 0) {
          await _applyInactivityDecay(db, periods);
        }
      }
    }
    return PlayerDb._(db);
  }

  static Future<void> _applyInactivityDecay(
      Database db, int periods) async {
    // One transaction across the player row AND every theme row. The player
    // row's updated_at stamp is what makes the decay idempotent, so a crash
    // after stamping it but before the theme loop finished would skip the
    // remaining themes permanently — the next launch sees periods == 0.
    await db.transaction((txn) async {
      Future<void> decayRow(String table, Map<String, Object?> row,
          String? whereId) async {
        final g = Glicko2(
          rating: (row['rating'] as num).toDouble(),
          rd: (row['rd'] as num).toDouble(),
          volatility: (row['vol'] as num).toDouble(),
        );
        for (var i = 0; i < periods; i++) {
          g.decay();
        }
        // Cap at the default initial RD so we don't infinitely inflate.
        final rd = g.rd.clamp(0.0, 350.0);
        // Stamping updated_at is what makes the decay idempotent. Without it
        // the next cold start recomputes the elapsed periods from the same
        // stale timestamp and decays again — five launches after an eight-day
        // gap apply eight days of decay five times over.
        await txn.update(
          table,
          {
            'rating': g.rating,
            'rd': rd,
            'vol': g.volatility,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: whereId == null ? 'id = 1' : 'theme_id = ?',
          whereArgs: whereId == null ? null : [whereId],
        );
      }

      final player = await txn.rawQuery(
          'SELECT rating, rd, vol FROM player WHERE id = 1');
      if (player.isNotEmpty) await decayRow('player', player.first, null);
      final themes = await txn
          .rawQuery('SELECT theme_id, rating, rd, vol FROM theme_rating');
      for (final r in themes) {
        await decayRow('theme_rating', r, r['theme_id'] as String);
      }
    });
  }

  Future<void> close() => _db.close();

  Future<Glicko2> globalRating() async {
    final rows = await _db.rawQuery('SELECT rating, rd, vol FROM player WHERE id = 1');
    final r = rows.first;
    return Glicko2(
      rating: (r['rating'] as num).toDouble(),
      rd: (r['rd'] as num).toDouble(),
      volatility: (r['vol'] as num).toDouble(),
    );
  }

  Future<Glicko2> themeRating(String themeId) async {
    final rows = await _db.rawQuery(
      'SELECT rating, rd, vol FROM theme_rating WHERE theme_id = ?',
      [themeId],
    );
    if (rows.isEmpty) {
      // First-time encounter with this theme: seed from the player's
      // GLOBAL rating so puzzles match their actual chess strength, not
      // a blank-slate 1200. Kept RD at 350 though — we don't know yet
      // whether this specific theme is a strength or a weakness.
      final global = await globalRating();
      return Glicko2(
        rating: global.rating,
        rd: 350.0,
        volatility: 0.06,
      );
    }
    final r = rows.first;
    return Glicko2(
      rating: (r['rating'] as num).toDouble(),
      rd: (r['rd'] as num).toDouble(),
      volatility: (r['vol'] as num).toDouble(),
    );
  }

  /// Batch fetch all theme ratings at once. ~30x faster than N round-trips
  /// when the dashboard loads.
  Future<Map<String, Glicko2>> allThemeRatings() async {
    final rows =
        await _db.rawQuery('SELECT theme_id, rating, rd, vol FROM theme_rating');
    return {
      for (final r in rows)
        r['theme_id'] as String: Glicko2(
          rating: (r['rating'] as num).toDouble(),
          rd: (r['rd'] as num).toDouble(),
          volatility: (r['vol'] as num).toDouble(),
        ),
    };
  }

  /// Calibration state: (done, step, target).
  Future<(bool, int, double)> calibrationState() async {
    final rows = await _db.rawQuery(
        'SELECT calibration_done, calibration_step, calibration_target '
        'FROM player WHERE id = 1');
    if (rows.isEmpty) return (true, 5, 1200.0);
    final r = rows.first;
    return (
      (r['calibration_done'] as int) == 1,
      r['calibration_step'] as int,
      (r['calibration_target'] as num).toDouble(),
    );
  }

  /// After a calibration puzzle resolves, record outcome and advance the
  /// state. When step reaches [Calibration.steps] - 1 and this is the
  /// final update, marks done and seeds rating.
  Future<void> advanceCalibration({required bool solved}) async {
    // One transaction: the read-advance-write must not interleave with
    // another writer, and the finishing pair (rating write + theme wipe) is
    // only meaningful together — a crash between them would leave the
    // calibrated rating live next to stale per-theme rows the finish is
    // documented to remove.
    await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
          'SELECT calibration_done, calibration_step, calibration_target '
          'FROM player WHERE id = 1');
      if (rows.isEmpty) return;
      final r = rows.first;
      if ((r['calibration_done'] as int) == 1) return;
      final step = r['calibration_step'] as int;
      final target = (r['calibration_target'] as num).toDouble();
      final nextTarget = Calibration.nextTarget(
          currentTarget: target, step: step, solved: solved);
      final nextStep = step + 1;
      final finished = nextStep >= Calibration.steps;
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'player',
        {
          'calibration_done': finished ? 1 : 0,
          'calibration_step': nextStep,
          'calibration_target': nextTarget,
          if (finished) 'rating': nextTarget,
          if (finished) 'rd': 120.0,
          'updated_at': now,
        },
        where: 'id = 1',
      );
      if (finished) {
        // Seed per-theme ratings too so the first post-calibration PLAY
        // uses the calibrated level everywhere. RD 120 = fairly confident.
        // (Existing theme_rating rows would be stale; wipe them.)
        await txn.delete('theme_rating');
      }
    });
  }

  /// Test seeding only. Production writes go through [commitResolution],
  /// which commits the attempt atomically with the rating and schedule.
  @visibleForTesting
  Future<void> recordAttempt({
    required String puzzleId,
    required String outcome,
    required String? firstWrongMoveUci,
    required double ratingDeltaGlobal,
    required int? solveDurationMs,
  }) async {
    await _db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('attempts', {
        'puzzle_id': puzzleId,
        'resolved_at': now,
        'outcome': outcome,
        'first_wrong_move_uci': firstWrongMoveUci,
        'rating_delta_global': ratingDeltaGlobal,
        'solve_duration_ms': solveDurationMs,
      });
      await txn.insert(
        'seen_recency',
        {'puzzle_id': puzzleId, 'last_seen': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Single-pass aggregate over the attempts table.
  ///
  /// One ordered scan of `attempts` (tiny: ~N entries), joined in Dart
  /// against the cached [themesByPuzzle] map. Replaces 4 separate
  /// overlapping scans; this is the fast warm-path (~1–5 ms typically
  /// even with thousands of attempts).
  Future<AttemptAggregates> aggregateAttempts(
    Map<String, List<String>> themesByPuzzle, {
    required int recentWindowPerTheme,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT puzzle_id, outcome, resolved_at
      FROM attempts
      ORDER BY resolved_at DESC
    ''');
    return AttemptAggregates.fromRows(
      rows,
      themesByPuzzle: themesByPuzzle,
      recentWindowPerTheme: recentWindowPerTheme,
    );
  }

  /// Set of puzzle ids the player has ever solved. Used by selection to
  /// tier candidates — never serve an already-solved puzzle when fresh
  /// ones exist.
  Future<Set<String>> solvedPuzzleIds() async {
    final rows = await _db.rawQuery(
        "SELECT DISTINCT puzzle_id FROM attempts WHERE outcome = 'solved'");
    return rows.map((r) => r['puzzle_id'] as String).toSet();
  }

  /// Per-theme rolling fail rate over the most recent N attempts. Returns
  /// null for themes the player has never attempted. Makes weakness scores
  /// respond fast — one failed puzzle in an N=10 window moves the rate
  /// by 0.1, which (at weakness weight 0.40) visibly bumps the % column.
  Future<Map<String, double>> recentFailRateByTheme(
    Map<String, List<String>> puzzleThemesMap, {
    int windowPerTheme = 10,
  }) async {
    // Grab the last ~windowPerTheme attempts PER THEME. Small theme count
    // (~25) × small window (10) keeps the result set tiny.
    final rows = await _db.rawQuery('''
      SELECT puzzle_id, outcome, resolved_at
      FROM attempts
      ORDER BY resolved_at DESC
    ''');
    final themeAttempts = <String, List<bool>>{}; // theme → list of solved?
    for (final r in rows) {
      final pid = r['puzzle_id'] as String;
      final themes = puzzleThemesMap[pid] ?? const <String>[];
      final solved = r['outcome'] == 'solved';
      for (final t in themes) {
        final buf = themeAttempts.putIfAbsent(t, () => <bool>[]);
        if (buf.length < windowPerTheme) buf.add(solved);
      }
    }
    final out = <String, double>{};
    themeAttempts.forEach((t, list) {
      if (list.isEmpty) return;
      final fails = list.where((s) => !s).length;
      out[t] = fails / list.length;
    });
    return out;
  }

  /// Total solved count across all puzzles.
  Future<int> totalSolvedCount() async {
    final row = await _db.rawQuery(
      'SELECT COUNT(DISTINCT puzzle_id) AS n FROM attempts WHERE outcome = ?',
      ['solved'],
    );
    return row.first['n'] as int;
  }

  Future<int> totalAttemptsCount() async {
    final row = await _db.rawQuery('SELECT COUNT(*) AS n FROM attempts');
    return row.first['n'] as int;
  }

  /// Distinct puzzles the player has ever attempted. The clear-rate
  /// denominator: NOT totalSolved + missedCount, because a puzzle solved
  /// once whose most recent attempt failed appears in both of those sets.
  Future<int> distinctSeenCount() async {
    final row = await _db
        .rawQuery('SELECT COUNT(DISTINCT puzzle_id) AS n FROM attempts');
    return row.first['n'] as int;
  }

  /// Puzzle ids whose MOST RECENT attempt was 'failed'. These are the
  /// puzzles the player hasn't cleared yet. Goal: shrink this list to zero.
  ///
  /// Uses a correlated subquery instead of ROW_NUMBER to stay compatible
  /// with all sqlite versions sqflite may ship against.
  Future<List<String>> missedPuzzleIds() async {
    final rows = await _db.rawQuery('''
      SELECT a.puzzle_id FROM attempts a
      WHERE a.outcome = 'failed'
        AND a.resolved_at = (
          SELECT MAX(b.resolved_at) FROM attempts b
          WHERE b.puzzle_id = a.puzzle_id
        )
      ORDER BY a.puzzle_id
    ''');
    return rows.map((r) => r['puzzle_id'] as String).toList();
  }

  /// Per-puzzle rolled-up stats: attempts / solves / fails / avg solve time.
  /// Excludes outlier attempts longer than [outlierCutoffMs] (default 3 min)
  /// from the duration average — the player likely put the phone down.
  Future<PuzzleStats?> puzzleStats(
    String puzzleId, {
    int outlierCutoffMs = 180000,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT outcome, solve_duration_ms
      FROM attempts WHERE puzzle_id = ?
      ''',
      [puzzleId],
    );
    if (rows.isEmpty) return null;
    int attempts = 0, solves = 0, fails = 0;
    final durations = <int>[];
    for (final r in rows) {
      attempts += 1;
      if (r['outcome'] == 'solved') {
        solves += 1;
      } else {
        fails += 1;
      }
      final d = r['solve_duration_ms'] as int?;
      if (d != null && d > 0 && d <= outlierCutoffMs) durations.add(d);
    }
    final avg = durations.isEmpty
        ? null
        : durations.fold<int>(0, (a, b) => a + b) / durations.length;
    return PuzzleStats(
      attempts: attempts,
      solves: solves,
      fails: fails,
      avgDurationMs: avg,
      samplesUsed: durations.length,
    );
  }

  /// Count of puzzles whose most-recent outcome was 'failed'.
  Future<int> missedCount() async {
    final row = await _db.rawQuery('''
      SELECT COUNT(*) AS n FROM attempts a
      WHERE a.outcome = 'failed'
        AND a.resolved_at = (
          SELECT MAX(b.resolved_at) FROM attempts b
          WHERE b.puzzle_id = a.puzzle_id
        )
    ''');
    return row.first['n'] as int;
  }

  Future<Map<String, DateTime>> seenRecency() async {
    final rows = await _db.rawQuery('SELECT puzzle_id, last_seen FROM seen_recency');
    final out = <String, DateTime>{};
    for (final r in rows) {
      out[r['puzzle_id'] as String] =
          DateTime.parse(r['last_seen'] as String);
    }
    return out;
  }

  /// One-row review lookup for [puzzleId]. Replaces full-table
  /// loadReviewQueue() in the hot finish-puzzle path so a 1-row query
  /// doesn't marshal the whole review set.
  static FsrsCard _cardFromRow(Map<String, Object?> r) => FsrsCard(
        stability: (r['stability'] as num).toDouble(),
        difficulty: (r['difficulty'] as num).toDouble(),
        due: DateTime.parse(r['due_at'] as String),
        lastReview: DateTime.parse(r['last_review'] as String),
        lastRating:
            Rating.values[((r['last_rating'] as int? ?? 1) - 1).clamp(0, 3)],
        reps: r['reps'] as int? ?? 0,
        lapses: r['lapses'] as int? ?? 0,
      );

  Future<FsrsCard?> reviewFor(String puzzleId) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM review_queue WHERE puzzle_id = ? LIMIT 1',
      [puzzleId],
    );
    if (rows.isEmpty) return null;
    return _cardFromRow(rows.first);
  }

  Future<Map<String, FsrsCard>> loadReviewQueue() async {
    final rows = await _db.rawQuery('SELECT * FROM review_queue');
    return {
      for (final r in rows) r['puzzle_id'] as String: _cardFromRow(r),
    };
  }

  /// Commit everything a resolved puzzle changes, atomically.
  ///
  /// Written as one transaction because these rows are only meaningful
  /// together. Applied piecemeal, a crash between the rating write and the
  /// attempt row leaves a player whose rating moved with no attempt to
  /// explain it — and every dashboard statistic (accuracy, XP, missed count,
  /// per-theme progress) is derived from `attempts`, so the discrepancy is
  /// permanent and invisible.
  ///
  /// The caller supplies already-computed values: rating and scheduling are
  /// pure functions of the outcome and belong outside the database layer.
  Future<void> commitResolution({
    required Glicko2 global,
    required Map<String, Glicko2> themeRatings,
    required String puzzleId,
    required String outcome,
    required String? firstWrongMoveUci,
    required double ratingDeltaGlobal,
    required int? solveDurationMs,
    FsrsCard? reviewCard,
    int reviewRating = 1,
    bool clearReview = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update('player', {
        'rating': global.rating,
        'rd': global.rd,
        'vol': global.volatility,
        'updated_at': now,
      }, where: 'id = 1');

      for (final entry in themeRatings.entries) {
        await txn.insert(
          'theme_rating',
          {
            'theme_id': entry.key,
            'rating': entry.value.rating,
            'rd': entry.value.rd,
            'vol': entry.value.volatility,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert('attempts', {
        'puzzle_id': puzzleId,
        'resolved_at': now,
        'outcome': outcome,
        'first_wrong_move_uci': firstWrongMoveUci,
        'rating_delta_global': ratingDeltaGlobal,
        'solve_duration_ms': solveDurationMs,
      });
      await txn.insert(
        'seen_recency',
        {'puzzle_id': puzzleId, 'last_seen': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (clearReview) {
        await txn.delete('review_queue',
            where: 'puzzle_id = ?', whereArgs: [puzzleId]);
      } else if (reviewCard != null) {
        await txn.insert(
          'review_queue',
          {
            'puzzle_id': puzzleId,
            'stability': reviewCard.stability,
            'difficulty': reviewCard.difficulty,
            'due_at':
                (reviewCard.due ?? DateTime.now()).toUtc().toIso8601String(),
            'last_review': (reviewCard.lastReview ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'last_rating': reviewRating,
            'reps': reviewCard.reps,
            'lapses': reviewCard.lapses,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Wipe all player state back to a fresh install.
  ///
  /// Atomic: five separate statements meant a crash partway through left the
  /// player with their history erased but their rating and calibration
  /// intact — a state no code path expects and the user cannot get out of by
  /// resetting again.
  Future<void> reset() async {
    await _db.transaction((txn) async {
      await txn.delete('attempts');
      await txn.delete('theme_rating');
      await txn.delete('review_queue');
      await txn.delete('seen_recency');
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update('player', {
        'rating': 1200.0, 'rd': 350.0, 'vol': 0.06,
        'updated_at': now,
        // Re-enter calibration: first 5 puzzles binary-search the level.
        'calibration_done': 0,
        'calibration_step': 0,
        'calibration_target': 1200.0,
      }, where: 'id = 1');
    });
  }
}

Future<File> playerDbFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'player.sqlite'));
}

/// Everything the journey snapshot needs from the attempts table, built in
/// one pass. See [PlayerDb.aggregateAttempts].
class AttemptAggregates {
  final Map<String, int> solvedByTheme;
  final Map<String, int> attemptedByTheme;
  final Map<String, double> recentFailRateByTheme;
  final Map<String, DateTime> lastAttemptPerTheme;
  const AttemptAggregates({
    required this.solvedByTheme,
    required this.attemptedByTheme,
    required this.recentFailRateByTheme,
    required this.lastAttemptPerTheme,
  });

  /// Build the aggregates from a list of `attempts` rows ordered by
  /// resolved_at DESC. Each row is expected to carry keys `puzzle_id`,
  /// `outcome` ('solved' or other), and `resolved_at` (ISO-8601 string).
  ///
  /// Pure function, testable independently of sqflite. Extracted from
  /// [PlayerDb.aggregateAttempts] so the per-theme counting logic has
  /// its own coverage without needing a real database.
  static AttemptAggregates fromRows(
    Iterable<Map<String, Object?>> rows, {
    required Map<String, List<String>> themesByPuzzle,
    required int recentWindowPerTheme,
  }) {
    final solvedByTheme = <String, int>{};
    final attemptedByTheme = <String, int>{};
    final recentAttemptsByTheme = <String, List<bool>>{};
    final lastAttemptPerTheme = <String, DateTime>{};
    final countedSolved = <String, Set<String>>{};
    final countedAttempted = <String, Set<String>>{};

    for (final r in rows) {
      final pid = r['puzzle_id'] as String;
      final outcome = r['outcome'] as String?;
      final solved = outcome == 'solved';
      final resolvedAtStr = r['resolved_at'] as String?;
      final resolvedAt =
          resolvedAtStr == null ? null : DateTime.tryParse(resolvedAtStr);

      final themes = themesByPuzzle[pid] ?? const <String>[];
      for (final t in themes) {
        final attSeen = countedAttempted.putIfAbsent(t, () => <String>{});
        if (attSeen.add(pid)) {
          attemptedByTheme[t] = (attemptedByTheme[t] ?? 0) + 1;
        }
        if (solved) {
          final slvSeen = countedSolved.putIfAbsent(t, () => <String>{});
          if (slvSeen.add(pid)) {
            solvedByTheme[t] = (solvedByTheme[t] ?? 0) + 1;
          }
        }
        final buf = recentAttemptsByTheme.putIfAbsent(t, () => <bool>[]);
        if (buf.length < recentWindowPerTheme) buf.add(solved);
        if (resolvedAt != null) {
          final cur = lastAttemptPerTheme[t];
          if (cur == null || resolvedAt.isAfter(cur)) {
            lastAttemptPerTheme[t] = resolvedAt;
          }
        }
      }
    }

    final recentFailRateByTheme = <String, double>{};
    recentAttemptsByTheme.forEach((t, list) {
      if (list.isEmpty) return;
      final fails = list.where((s) => !s).length;
      recentFailRateByTheme[t] = fails / list.length;
    });

    return AttemptAggregates(
      solvedByTheme: solvedByTheme,
      attemptedByTheme: attemptedByTheme,
      recentFailRateByTheme: recentFailRateByTheme,
      lastAttemptPerTheme: lastAttemptPerTheme,
    );
  }
}
