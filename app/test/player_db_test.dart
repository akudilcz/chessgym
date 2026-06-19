import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// These tests exercise the SQL schema and ConflictAlgorithm behavior used
// by PlayerDb. They avoid path_provider (which needs Flutter channels) by
// hitting an in-memory sqflite_common_ffi database directly.

const _schema = '''
CREATE TABLE player (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  rating REAL NOT NULL, rd REAL NOT NULL, vol REAL NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  board_flipped_default INTEGER NOT NULL DEFAULT 0,
  sound_on INTEGER NOT NULL DEFAULT 1,
  high_contrast INTEGER NOT NULL DEFAULT 0,
  piece_set TEXT NOT NULL DEFAULT 'cburnett',
  reduced_motion INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE theme_rating (
  theme_id TEXT PRIMARY KEY,
  rating REAL NOT NULL, rd REAL NOT NULL, vol REAL NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE attempts (
  puzzle_id TEXT NOT NULL, resolved_at TEXT NOT NULL,
  outcome TEXT NOT NULL, first_wrong_move_uci TEXT,
  rating_delta_global REAL NOT NULL,
  PRIMARY KEY (puzzle_id, resolved_at)
);
CREATE TABLE review_queue (
  puzzle_id TEXT PRIMARY KEY,
  stability REAL NOT NULL, difficulty REAL NOT NULL,
  due_at TEXT NOT NULL, last_review TEXT NOT NULL,
  last_rating INTEGER NOT NULL
);
CREATE TABLE seen_recency (
  puzzle_id TEXT PRIMARY KEY, last_seen TEXT NOT NULL
);
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> freshDb() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1));
    for (final stmt in _schema.split(';')) {
      final s = stmt.trim();
      if (s.isNotEmpty) await db.execute(s);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('player', {
      'id': 1, 'rating': 800.0, 'rd': 350.0, 'vol': 0.06,
      'created_at': now, 'updated_at': now,
    });
    return db;
  }

  test('attempts table records both outcomes', () async {
    final db = await freshDb();
    await db.insert('attempts', {
      'puzzle_id': 'a',
      'resolved_at': '2026-01-01T00:00:00Z',
      'outcome': 'solved',
      'first_wrong_move_uci': null,
      'rating_delta_global': 8.0,
    });
    await db.insert('attempts', {
      'puzzle_id': 'b',
      'resolved_at': '2026-01-01T00:00:01Z',
      'outcome': 'failed',
      'first_wrong_move_uci': 'e2e3',
      'rating_delta_global': -6.0,
    });
    final rows = await db.query('attempts', orderBy: 'resolved_at');
    expect(rows.length, 2);
    expect(rows[0]['outcome'], 'solved');
    expect(rows[1]['outcome'], 'failed');
    await db.close();
  });

  test('review_queue upsert replaces on conflict', () async {
    final db = await freshDb();
    Future<void> upsert(FsrsCard c, int rating) => db.insert(
          'review_queue',
          {
            'puzzle_id': 'p1',
            'stability': c.stability,
            'difficulty': c.difficulty,
            'due_at': (c.due ?? DateTime.now()).toIso8601String(),
            'last_review':
                (c.lastReview ?? DateTime.now()).toIso8601String(),
            'last_rating': rating,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    final c = FsrsCard();
    Fsrs().review(c, Rating.again, DateTime.utc(2026, 1, 1));
    await upsert(c, 1);
    // "Continue" the same card — reviewing as Good at a later date should
    // upsert-replace the single row (PRIMARY KEY on puzzle_id).
    Fsrs().review(c, Rating.good, DateTime.utc(2026, 1, 5));
    await upsert(c, 3);
    final rows = await db.query('review_queue', where: 'puzzle_id = ?', whereArgs: ['p1']);
    expect(rows.length, 1);
    expect(rows.first['last_rating'], 3);
    await db.close();
  });

  test('removing a review empties the queue', () async {
    final db = await freshDb();
    await db.insert('review_queue', {
      'puzzle_id': 'x',
      'stability': 1.0,
      'difficulty': 5.0,
      'due_at': '2026-01-01T00:00:00Z',
      'last_review': '2026-01-01T00:00:00Z',
      'last_rating': 3,
    });
    await db.delete('review_queue', where: 'puzzle_id = ?', whereArgs: ['x']);
    final rows = await db.query('review_queue');
    expect(rows, isEmpty);
    await db.close();
  });

  test('reset wipes all player state', () async {
    final db = await freshDb();
    await db.insert('attempts', {
      'puzzle_id': 'a', 'resolved_at': 't',
      'outcome': 'solved', 'first_wrong_move_uci': null,
      'rating_delta_global': 1.0,
    });
    await db.insert('review_queue', {
      'puzzle_id': 'r', 'stability': 1, 'difficulty': 5,
      'due_at': 't', 'last_review': 't', 'last_rating': 1,
    });
    await db.delete('attempts');
    await db.delete('review_queue');
    expect((await db.query('attempts')), isEmpty);
    expect((await db.query('review_queue')), isEmpty);
    await db.close();
  });
}
