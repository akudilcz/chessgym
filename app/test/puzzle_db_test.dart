import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Lightweight integration test: open an in-memory sqflite DB matching
/// our schema, seed one puzzle, read it back, and verify joins.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('seeded puzzle round-trips through schema', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('''
      CREATE TABLE puzzles (
        id TEXT PRIMARY KEY, fen TEXT, setup_move TEXT, side_to_move TEXT,
        moves_uci TEXT, rating INTEGER, rating_dev INTEGER,
        popularity INTEGER, nb_plays INTEGER, interest REAL,
        origin_kind TEXT, origin_label TEXT, explanation TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE themes (
        id TEXT PRIMARY KEY, display_name TEXT, description TEXT,
        importance REAL, floor_rating INTEGER, ceiling_rating INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE puzzle_themes (
        puzzle_id TEXT, theme_id TEXT, position INTEGER,
        PRIMARY KEY (puzzle_id, theme_id)
      )
    ''');
    await db.insert('themes', {
      'id': 'fork', 'display_name': 'Fork', 'description': 'x',
      'importance': 1.0, 'floor_rating': 800, 'ceiling_rating': 2000,
    });
    await db.insert('puzzles', {
      'id': 'p1',
      'fen': '6k1/5ppp/8/8/8/8/5PPP/R4K2 w - - 0 1',
      'setup_move': '', 'side_to_move': 'w', 'moves_uci': 'a1a8',
      'rating': 1200, 'rating_dev': 80, 'popularity': 95, 'nb_plays': 3000,
      'interest': 0.8, 'origin_kind': 'lichess',
      'origin_label': null, 'explanation': null,
    });
    await db.insert('puzzle_themes', {
      'puzzle_id': 'p1', 'theme_id': 'fork', 'position': 0,
    });

    // Query shape matches the app's PuzzleDb.candidatesForTheme.
    final rows = await db.rawQuery('''
      SELECT p.id, p.rating, GROUP_CONCAT(pt.theme_id, ',') AS themes
      FROM puzzles p
      INNER JOIN puzzle_themes pt_f
        ON pt_f.puzzle_id = p.id AND pt_f.theme_id = ?
      LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      WHERE p.rating BETWEEN ? AND ?
      GROUP BY p.id
    ''', ['fork', 1000, 1400]);
    expect(rows.length, 1);
    expect(rows.first['id'], 'p1');
    expect(rows.first['themes'], 'fork');
    await db.close();
  });
}
