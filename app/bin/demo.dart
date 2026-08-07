// Terminal demo of the solve flow: opens the shipped puzzles.sqlite,
// picks a puzzle, and walks through solving it as if the user were
// playing — showing the board in ASCII, the scripted solution, and
// the state transitions (rating delta, review scheduling).
//
// Run: dart run bin/demo.dart [puzzle_id]
//
// This is NOT part of the shipped app — it's a harness so humans can
// watch the code work on a machine without Flutter UI support.

// This is a terminal harness, not shipped app code: stdout is its
// entire user interface, so print is the right call here.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chesspuzzle/data/puzzle_controller.dart';
import 'package:chesspuzzle/domain/puzzle.dart';

import 'package:path/path.dart' as p;

String get _assetPath =>
    p.absolute(p.join(Directory.current.path, 'assets/puzzles/puzzles.sqlite'));

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    _assetPath,
    options: OpenDatabaseOptions(readOnly: true),
  );

  final puzzle = args.isNotEmpty
      ? await _byId(db, args.first)
      : await _randomPuzzle(db);
  if (puzzle == null) {
    stderr.writeln('No puzzle found.');
    exit(1);
  }

  _printHeader(puzzle);

  final ctrl = PuzzleController(puzzle);
  print('\nStarting position:');
  _printBoard(ctrl.position);

  // Player = Glicko-2 defaults.
  final player = Glicko2();
  print('\nPlayer rating before: ${player.rating.toStringAsFixed(0)} '
      '(RD ${player.rd.toStringAsFixed(0)})');

  // Play through the scripted solution automatically.
  print('\n--- Solving (playing scripted solution move-by-move) ---');
  int solverTurn = 0;
  for (int ply = 0; ply < puzzle.moves.length; ply += 2) {
    final solverMove = puzzle.moves[ply];
    solverTurn += 1;
    stdout.write('Move $solverTurn: playing $solverMove ... ');
    final r = ctrl.tryMove(solverMove);
    if (!r.accepted) {
      print('REJECTED');
      break;
    }
    print('ok${r.opponentReply?.uci != null ? " (reply: ${r.opponentReply?.uci})" : ""}');
    _printBoard(ctrl.position);
    if (r.puzzleComplete) break;
  }

  print('\nFinal state: ${ctrl.state.name}');

  // Update rating, simulate review scheduling.
  final solved = ctrl.state == SolveState.succeeded;
  final before = player.rating;
  player.update(
    opponentRating: puzzle.rating.toDouble(),
    opponentRd: puzzle.ratingDev.toDouble(),
    score: solved ? 1.0 : 0.0,
  );
  final delta = player.rating - before;
  print('Player rating after:  ${player.rating.toStringAsFixed(0)} '
      '(${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)})');

  if (!solved) {
    final card = FsrsCard();
    Fsrs().review(card, Rating.again, DateTime.now().toUtc());
    print('FSRS: scheduled review — due ${card.due!.toIso8601String()}');
  } else {
    print('FSRS: no review needed (solved first try).');
  }

  await db.close();
}

Future<Puzzle?> _byId(Database db, String id) async {
  final rows = await db.rawQuery('''
    SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
    FROM puzzles p
    LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
    WHERE p.id = ?
    GROUP BY p.id
  ''', [id]);
  if (rows.isEmpty) return null;
  return _rowToPuzzle(rows.first);
}

Future<Puzzle?> _randomPuzzle(Database db) async {
  final rows = await db.rawQuery('''
    SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
    FROM puzzles p
    LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
    GROUP BY p.id
    ORDER BY p.interest DESC
    LIMIT 50
  ''');
  if (rows.isEmpty) return null;
  final rng = math.Random();
  return _rowToPuzzle(rows[rng.nextInt(rows.length)]);
}

Puzzle _rowToPuzzle(Map<String, Object?> r) {
  final themeStr = (r['theme_ids'] as String?) ?? '';
  return Puzzle(
    id: r['id'] as String,
    fen: r['fen'] as String,
    setupMove: r['setup_move'] as String,
    sideToMove: r['side_to_move'] as String,
    moves: (r['moves_uci'] as String).split(' '),
    rating: r['rating'] as int,
    ratingDev: r['rating_dev'] as int,
    popularity: r['popularity'] as int,
    nbPlays: r['nb_plays'] as int,
    interest: (r['interest'] as num).toDouble(),
    originKind: r['origin_kind'] as String,
    originLabel: r['origin_label'] as String?,
    explanation: r['explanation'] as String?,
    themes: themeStr.isEmpty ? const [] : themeStr.split(','),
  );
}

void _printHeader(Puzzle p) {
  print('=' * 60);
  print('Puzzle ${p.id}');
  print('  rating     : ${p.rating} (RD ${p.ratingDev})');
  print('  interest   : ${p.interest.toStringAsFixed(3)}');
  print('  themes     : ${p.themes.join(", ")}');
  if (p.originLabel != null) {
    print('  origin     : ${p.originLabel}');
  }
  if (p.explanation != null) {
    print('  explanation: ${p.explanation}');
  }
  print('  to move    : ${p.sideToMove == "w" ? "White" : "Black"}');
  print('  solution   : ${p.moves.join(" ")}');
  print('=' * 60);
}

void _printBoard(Position pos) {
  // Render the FEN to an 8x8 ASCII grid using Unicode piece glyphs.
  const glyph = {
    'K': '♔', 'Q': '♕', 'R': '♖', 'B': '♗', 'N': '♘', 'P': '♙',
    'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟',
  };
  final boardFen = pos.fen.split(' ').first;
  final rows = boardFen.split('/');
  for (var r = 0; r < 8; r++) {
    stdout.write('  ${8 - r} ');
    for (final ch in rows[r].split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        stdout.write(' . ' * n);
      } else {
        stdout.write(' ${glyph[ch] ?? ch} ');
      }
    }
    stdout.writeln();
  }
  print('     a  b  c  d  e  f  g  h');
}
