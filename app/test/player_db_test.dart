import 'package:chesspuzzle/data/player_db.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

// These tests drive the REAL PlayerDb — its schema, migrations and
// transactional writes — over temp files via TestHarness. An earlier version
// re-declared the schema by hand inside this file, which let the two drift
// apart and hid a bug where FSRS review state was never fully persisted.

void main() {
  initSqfliteForTests();

  late TestHarness h;
  setUp(() async => h = await TestHarness.create());
  tearDown(() async => h.dispose());

  Future<void> commit({
    required String puzzleId,
    required String outcome,
    FsrsCard? reviewCard,
    int reviewRating = 1,
    bool clearReview = false,
  }) {
    return h.playerDb.commitResolution(
      global: Glicko2(rating: 1210, rd: 300, volatility: 0.06),
      themeRatings: {'fork': Glicko2(rating: 1180, rd: 320, volatility: 0.06)},
      puzzleId: puzzleId,
      outcome: outcome,
      firstWrongMoveUci: outcome == 'failed' ? 'e2e3' : null,
      ratingDeltaGlobal: outcome == 'solved' ? 8.0 : -6.0,
      solveDurationMs: 4200,
      reviewCard: reviewCard,
      reviewRating: reviewRating,
      clearReview: clearReview,
    );
  }

  test('commitResolution records attempts for both outcomes', () async {
    await commit(puzzleId: 'a', outcome: 'solved');
    await commit(puzzleId: 'b', outcome: 'failed');
    final agg = await h.playerDb.aggregateAttempts(
      {
        'a': ['fork'],
        'b': ['fork'],
      },
      recentWindowPerTheme: 10,
    );
    expect(agg.solvedByTheme['fork'], 1);
    expect(agg.attemptedByTheme['fork'], 2);
  });

  test('review card round-trips with its full FSRS state', () async {
    final fsrs = Fsrs();
    final card = FsrsCard();
    fsrs.review(card, Rating.again, DateTime.utc(2026, 1, 1));
    fsrs.review(card, Rating.good, DateTime.utc(2026, 1, 3));
    await commit(
      puzzleId: 'p1',
      outcome: 'solved',
      reviewCard: card,
      reviewRating: ratingToInt(Rating.good),
    );

    final loaded = await h.playerDb.reviewFor('p1');
    expect(loaded, isNotNull);
    expect(loaded!.stability, closeTo(card.stability, 1e-9));
    expect(loaded.difficulty, closeTo(card.difficulty, 1e-9));
    expect(loaded.reps, card.reps);
    expect(loaded.lapses, card.lapses);
    expect(loaded.lastRating, Rating.good);
    // The load-bearing property: a rehydrated card must NOT look new, or
    // the next review re-initializes it and the interval never grows.
    expect(loaded.isNew, isFalse);
    fsrs.review(loaded, Rating.good, DateTime.utc(2026, 1, 20));
    expect(loaded.stability, greaterThan(card.stability));
  });

  test('clearReview removes the card; upsert keeps a single row', () async {
    final card = FsrsCard();
    Fsrs().review(card, Rating.again, DateTime.utc(2026, 1, 1));
    await commit(puzzleId: 'p1', outcome: 'failed', reviewCard: card);
    await commit(
      puzzleId: 'p1',
      outcome: 'solved',
      reviewCard: card,
      reviewRating: ratingToInt(Rating.good),
    );
    expect((await h.playerDb.loadReviewQueue()).length, 1);
    await commit(puzzleId: 'p1', outcome: 'solved', clearReview: true);
    expect(await h.playerDb.reviewFor('p1'), isNull);
  });

  test('reset wipes attempts, queue and re-enters calibration', () async {
    final card = FsrsCard();
    Fsrs().review(card, Rating.again, DateTime.utc(2026, 1, 1));
    await commit(puzzleId: 'p1', outcome: 'failed', reviewCard: card);
    await h.playerDb.reset();
    expect(await h.playerDb.loadReviewQueue(), isEmpty);
    final (done, step, target) = await h.playerDb.calibrationState();
    expect(done, isFalse);
    expect(step, 0);
    expect(target, 1200.0);
    final g = await h.playerDb.globalRating();
    expect(g.rating, 1200.0);
    expect(g.rd, 350.0);
  });

  test('advanceCalibration walks the binary search and finishes atomically',
      () async {
    // Fresh install: calibration is pending.
    var (done, step, target) = await h.playerDb.calibrationState();
    expect(done, isFalse);
    for (final solved in [true, true, false, true, false]) {
      await h.playerDb.advanceCalibration(solved: solved);
    }
    (done, step, target) = await h.playerDb.calibrationState();
    expect(done, isTrue);
    expect(step, 5);
    // 1200 +300 +300 -200 +100 -50 = 1650.
    expect(target, 1650.0);
    final g = await h.playerDb.globalRating();
    expect(g.rating, 1650.0);
    expect(g.rd, 120.0);
    // Finishing wipes stale per-theme ratings.
    expect(await h.playerDb.allThemeRatings(), isEmpty);
  });

  test('opening a pre-reps database migrates review_queue in place', () async {
    final path = p.join(h.dir.path, 'legacy_player.sqlite');
    final db = await databaseFactory.openDatabase(path);
    await db.execute('''
CREATE TABLE review_queue (
  puzzle_id TEXT PRIMARY KEY,
  stability REAL NOT NULL, difficulty REAL NOT NULL,
  due_at TEXT NOT NULL, last_review TEXT NOT NULL,
  last_rating INTEGER NOT NULL
)''');
    await db.insert('review_queue', {
      'puzzle_id': 'legacy',
      'stability': 3.5,
      'difficulty': 6.0,
      'due_at': '2026-01-05T00:00:00Z',
      'last_review': '2026-01-01T00:00:00Z',
      'last_rating': 3,
    });
    await db.close();

    final legacy = await PlayerDb.open(playerDbPath: path);
    addTearDown(legacy.close);
    final card = await legacy.reviewFor('legacy');
    expect(card, isNotNull);
    expect(card!.stability, closeTo(3.5, 1e-9));
    expect(card.reps, 0);
    expect(card.lapses, 0);
    expect(card.lastRating, Rating.good);
    expect(card.isNew, isFalse,
        reason: 'a migrated card has history and must not be re-initialized');
  });
}
