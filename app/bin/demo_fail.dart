// Second demo: intentionally play a wrong first move and watch
// PuzzleController → state=failed → FSRS schedule the review.

import 'dart:io';

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:dartchess/dartchess.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chesspuzzle/data/puzzle_controller.dart';
import 'package:chesspuzzle/domain/puzzle.dart';

String get _assetPath =>
    p.absolute(p.join(Directory.current.path, 'assets/puzzles/puzzles.sqlite'));

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    _assetPath,
    options: OpenDatabaseOptions(readOnly: true),
  );

  // Pick the highest-interest Lichess puzzle (not famous).
  final rows = await db.rawQuery('''
    SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
    FROM puzzles p
    LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
    WHERE p.origin_kind = 'lichess'
    GROUP BY p.id
    ORDER BY p.interest DESC
    LIMIT 1
  ''');
  if (rows.isEmpty) {
    stderr.writeln('empty db');
    exit(1);
  }
  final r = rows.first;
  final themeStr = (r['theme_ids'] as String?) ?? '';
  final puzzle = Puzzle(
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
    originLabel: null,
    explanation: null,
    themes: themeStr.isEmpty ? const [] : themeStr.split(','),
  );

  print('Puzzle ${puzzle.id}  rating ${puzzle.rating}  '
      'themes ${puzzle.themes.take(3).join(",")}');
  print('True solution first move: ${puzzle.moves.first}');

  final ctrl = PuzzleController(puzzle);
  // Pick any legal move that isn't the correct one.
  final correct = puzzle.moves.first;
  final wrong = ctrl.position.legalMoves.entries
      .expand((e) => e.value.squares.map((to) =>
          NormalMove(from: e.key, to: to).uci))
      .firstWhere((m) => m != correct && !m.endsWith('q') && !m.endsWith('r'),
          orElse: () => '');
  print('Trying wrong move: $wrong');

  final result = ctrl.tryMove(wrong);
  print('Accepted: ${result.accepted}  state: ${ctrl.state.name}');
  print('First wrong UCI recorded: ${ctrl.firstWrongUci}');

  final player = Glicko2();
  final before = player.rating;
  player.update(
    opponentRating: puzzle.rating.toDouble(),
    opponentRd: puzzle.ratingDev.toDouble(),
    score: 0.0,
  );
  print('Player rating: ${before.toStringAsFixed(0)} → '
      '${player.rating.toStringAsFixed(0)} '
      '(${(player.rating - before).toStringAsFixed(1)})');

  final card = FsrsCard();
  Fsrs().review(card, Rating.again, DateTime.now().toUtc());
  final hoursOut = card.due!.difference(DateTime.now().toUtc()).inHours;
  print('FSRS: next review in ${hoursOut}h  '
      '(stability ${card.stability.toStringAsFixed(2)}d, '
      'difficulty ${card.difficulty.toStringAsFixed(2)})');

  await db.close();
}
