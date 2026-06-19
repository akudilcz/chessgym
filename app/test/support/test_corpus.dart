import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds a real, on-disk `puzzles.sqlite` that matches the production
/// corpus schema byte-for-byte in structure.
///
/// The 58 MB shipped asset is unusable from a test: it is slow, it makes
/// assertions depend on whatever the pipeline last emitted, and it forces
/// `PuzzleDb.open()` down the asset-copy path (which needs platform
/// channels). Instead every test builds its own tiny corpus here and hands
/// the file to `PuzzleDb.openAt`, so the real query methods run against
/// real SQLite with a schema we control.
///
/// [corpusSchemaSql] is a verbatim copy of `SCHEMA` in
/// `pipeline/stages/emit.py`. `schema_sync_test.dart` fails if the two ever
/// drift, so this copy cannot silently rot.
const String corpusSchemaSql = '''
CREATE TABLE puzzles (
  id            TEXT PRIMARY KEY,
  fen           TEXT NOT NULL,
  setup_move    TEXT NOT NULL,
  side_to_move  TEXT NOT NULL CHECK(side_to_move IN ('w','b')),
  moves_uci     TEXT NOT NULL,
  rating        INTEGER NOT NULL,
  rating_dev    INTEGER NOT NULL,
  popularity    INTEGER NOT NULL,
  nb_plays      INTEGER NOT NULL,
  interest      REAL NOT NULL,
  origin_kind   TEXT NOT NULL CHECK(origin_kind IN ('lichess','study','famous')),
  origin_label  TEXT,
  explanation   TEXT
);
CREATE INDEX idx_puzzles_rating ON puzzles(rating);
CREATE INDEX idx_puzzles_interest ON puzzles(interest DESC);

CREATE TABLE puzzle_themes (
  puzzle_id TEXT NOT NULL REFERENCES puzzles(id),
  theme_id  TEXT NOT NULL REFERENCES themes(id),
  position  INTEGER NOT NULL,
  PRIMARY KEY (puzzle_id, theme_id)
);
CREATE INDEX idx_puzzle_themes_theme ON puzzle_themes(theme_id);

CREATE TABLE themes (
  id             TEXT PRIMARY KEY,
  display_name   TEXT NOT NULL,
  description    TEXT NOT NULL,
  importance     REAL NOT NULL,
  floor_rating   INTEGER NOT NULL,
  ceiling_rating INTEGER NOT NULL
);

CREATE TABLE theme_prereqs (
  theme_id   TEXT NOT NULL REFERENCES themes(id),
  prereq_id  TEXT NOT NULL REFERENCES themes(id),
  PRIMARY KEY (theme_id, prereq_id)
);

CREATE TABLE daily_index (
  slot       INTEGER PRIMARY KEY,
  puzzle_id  TEXT NOT NULL REFERENCES puzzles(id)
);

CREATE TABLE corpus_meta (
  version      TEXT NOT NULL,
  built_at     TEXT NOT NULL,
  source_hash  TEXT NOT NULL,
  n_puzzles    INTEGER NOT NULL,
  n_themes     INTEGER NOT NULL
);
''';

/// One row of `themes` (+ its `theme_prereqs` rows).
class TestTheme {
  final String id;
  final String displayName;
  final String description;
  final double importance;
  final int floorRating;
  final int ceilingRating;
  final List<String> prereqs;

  const TestTheme({
    required this.id,
    required this.displayName,
    this.description = 'A tactical motif.',
    this.importance = 1.0,
    this.floorRating = 600,
    this.ceilingRating = 2200,
    this.prereqs = const [],
  });
}

/// One row of `puzzles` (+ its `puzzle_themes` rows).
///
/// Every default puzzle below is a legal position whose scripted line has
/// been verified against dartchess by `corpus_test.dart`.
class TestPuzzle {
  final String id;
  final String fen;
  final String setupMove;
  final String sideToMove;
  final List<String> moves;
  final int rating;
  final int ratingDev;
  final int popularity;
  final int nbPlays;
  final double interest;
  final String originKind;
  final String? originLabel;
  final String? explanation;
  final List<String> themes;

  const TestPuzzle({
    required this.id,
    required this.fen,
    required this.moves,
    required this.rating,
    this.setupMove = '',
    this.sideToMove = 'w',
    this.ratingDev = 75,
    this.popularity = 90,
    this.nbPlays = 1000,
    this.interest = 0.5,
    this.originKind = 'lichess',
    this.originLabel,
    this.explanation,
    this.themes = const [],
  });
}

const List<TestTheme> kTestThemes = [
  TestTheme(
    id: 'mateIn1',
    displayName: 'Mate in one',
    description: 'Deliver checkmate in a single move.',
    importance: 1.0,
    floorRating: 600,
    ceilingRating: 1800,
  ),
  TestTheme(
    id: 'backRankMate',
    displayName: 'Back rank mate',
    description: 'Mate along the back rank.',
    importance: 0.8,
    floorRating: 700,
    ceilingRating: 2000,
    // Exercises PuzzleDb.listThemes' theme_prereqs GROUP_CONCAT branch.
    prereqs: ['mateIn1'],
  ),
  TestTheme(
    id: 'endgame',
    displayName: 'Endgame',
    description: 'Few pieces left on the board.',
    importance: 0.6,
    floorRating: 800,
    ceilingRating: 2200,
  ),
  TestTheme(
    id: 'fork',
    displayName: 'Fork',
    description: 'Attack two pieces at once.',
    importance: 0.9,
    floorRating: 900,
    ceilingRating: 2100,
  ),
];

/// Ratings are chosen so that **exactly one** puzzle (`p-mate1-w`, 1200)
/// sits inside the calibration band 1200 ± 100. A fresh `PlayerDb` starts
/// un-calibrated, so `SelectionService.pickNext` short-circuits to
/// `puzzleNearRating(1200)` — which therefore deterministically serves
/// `p-mate1-w`. Keep that property when editing this list, or the
/// "PLAY serves a puzzle" tests lose their determinism.
const List<TestPuzzle> kTestPuzzles = [
  // Solver = white, one ply, back-rank mate. Ra1-a8#.
  TestPuzzle(
    id: 'p-mate1-w',
    fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
    moves: ['a1a8'],
    rating: 1200,
    interest: 0.99,
    explanation: 'The back rank is fatally weak.',
    originLabel: 'Test corpus',
    themes: ['mateIn1', 'backRankMate'],
  ),
  // Solver = black, one ply, back-rank mate. Ra8-a1#.
  TestPuzzle(
    id: 'p-mate1-b',
    fen: 'r5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1',
    sideToMove: 'b',
    moves: ['a8a1'],
    rating: 900,
    interest: 0.80,
    themes: ['mateIn1'],
  ),
  // Three plies: solver move, scripted opponent reply, solver move.
  // Ra1-a8+ Kg8-h7 (forced) Ra8-a7.
  TestPuzzle(
    id: 'p-threeply',
    fen: '6k1/5pp1/7p/8/8/8/5PPP/R5K1 w - - 0 1',
    moves: ['a1a8', 'g8h7', 'a8a7'],
    rating: 1500,
    interest: 0.70,
    themes: ['endgame', 'backRankMate'],
  ),
  // Non-empty setup_move: the opponent's move is replayed before the
  // solver gets control (Kg8-h8, then Ra2-a8#).
  TestPuzzle(
    id: 'p-setupmove',
    fen: '6k1/5ppp/8/8/8/8/R4PPP/6K1 b - - 0 1',
    setupMove: 'g8h8',
    moves: ['a2a8'],
    rating: 700,
    interest: 0.60,
    themes: ['mateIn1', 'endgame'],
  ),
  // High-rated filler so rating bands and theme totals have spread.
  TestPuzzle(
    id: 'p-hard',
    fen: '6k1/5ppp/8/8/8/8/5PPP/1R4K1 w - - 0 1',
    moves: ['b1b8'],
    rating: 2000,
    interest: 0.40,
    themes: ['fork', 'endgame'],
  ),
];

/// Writes a corpus at [path] and returns that path.
///
/// [databaseFactory] must already be the FFI factory (see
/// `harness.dart#initSqfliteForTests`).
Future<String> buildTestCorpus(
  String path, {
  List<TestPuzzle> puzzles = kTestPuzzles,
  List<TestTheme> themes = kTestThemes,
  String version = 'test-1',
}) async {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  f.parent.createSync(recursive: true);

  final db = await databaseFactory.openDatabase(path);
  try {
    for (final stmt in corpusSchemaSql.split(';')) {
      final s = stmt.trim();
      if (s.isNotEmpty) await db.execute(s);
    }
    for (final t in themes) {
      await db.insert('themes', {
        'id': t.id,
        'display_name': t.displayName,
        'description': t.description,
        'importance': t.importance,
        'floor_rating': t.floorRating,
        'ceiling_rating': t.ceilingRating,
      });
      for (final pr in t.prereqs) {
        await db.insert('theme_prereqs', {'theme_id': t.id, 'prereq_id': pr});
      }
    }
    for (final p in puzzles) {
      await db.insert('puzzles', {
        'id': p.id,
        'fen': p.fen,
        'setup_move': p.setupMove,
        'side_to_move': p.sideToMove,
        'moves_uci': p.moves.join(' '),
        'rating': p.rating,
        'rating_dev': p.ratingDev,
        'popularity': p.popularity,
        'nb_plays': p.nbPlays,
        'interest': p.interest,
        'origin_kind': p.originKind,
        'origin_label': p.originLabel,
        'explanation': p.explanation,
      });
      for (var i = 0; i < p.themes.length; i++) {
        await db.insert('puzzle_themes', {
          'puzzle_id': p.id,
          'theme_id': p.themes[i],
          'position': i,
        });
      }
    }
    // daily_index mirrors the pipeline: interest DESC, id as tiebreak.
    final daily = [...puzzles]..sort((a, b) {
        final c = b.interest.compareTo(a.interest);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    for (var i = 0; i < daily.length; i++) {
      await db.insert('daily_index', {'slot': i, 'puzzle_id': daily[i].id});
    }
    await db.insert('corpus_meta', {
      'version': version,
      'built_at': '2026-01-01T00:00:00+00:00',
      'source_hash': 'testhash00000000',
      'n_puzzles': puzzles.length,
      'n_themes': themes.length,
    });
  } finally {
    await db.close();
  }
  return path;
}
