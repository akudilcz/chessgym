import 'package:chessground/chessground.dart' as cg;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers for driving the chessground board the way a player does:
/// tap the piece, tap the destination. Coordinates come from the board's
/// own `board-container` key, so they stay correct whatever size the
/// solve screen picks.

Finder get boardFinder => find.byType(cg.Chessboard);

Side boardOrientation(WidgetTester tester) =>
    tester.widget<cg.Chessboard>(boardFinder).orientation;

/// The pieces currently on the board, by square.
///
/// Since chessground 10 the board paints pieces onto a canvas instead of
/// building one keyed widget per square, so `find.byKey('a1-whiterook')`
/// finds nothing. The controller's piece map is the equivalent — and it is
/// what the painter itself draws from.
Map<Square, Piece> boardPieces(WidgetTester tester) =>
    tester.widget<cg.Chessboard>(boardFinder).controller.pieces;

/// Asserts that [square] holds exactly the piece described by [pieceKey],
/// written the way chessground used to key them: `'a1-whiterook'`.
void expectPiece(WidgetTester tester, String pieceKey) {
  const roles = {
    'pawn': Role.pawn, 'knight': Role.knight, 'bishop': Role.bishop,
    'rook': Role.rook, 'queen': Role.queen, 'king': Role.king,
  };
  final parts = pieceKey.split('-');
  final square = Square.fromName(parts[0]);
  final side = parts[1].startsWith('white') ? Side.white : Side.black;
  final role = roles[parts[1].replaceFirst(RegExp('^(white|black)'), '')]!;
  expect(
    boardPieces(tester)[square],
    Piece(color: side, role: role),
    reason: pieceKey,
  );
}

/// Asserts that [square] is empty.
void expectNoPiece(WidgetTester tester, Square square) {
  expect(boardPieces(tester)[square], isNull, reason: square.name);
}

/// Centre of [square] in global coordinates.
Offset squareOffset(WidgetTester tester, Square square, {Side? orientation}) {
  final side = orientation ?? boardOrientation(tester);
  final rect = tester.getRect(find.byKey(const ValueKey('board-container')));
  final sq = rect.width / 8;
  final x = side == Side.black ? 7 - square.file : square.file;
  final y = side == Side.black ? square.rank : 7 - square.rank;
  return Offset(rect.left + (x + 0.5) * sq, rect.top + (y + 0.5) * sq);
}

/// Plays `from`→`to` with two taps (chessground's
/// `PieceShiftMethod.either` accepts tap-tap as well as drag).
Future<void> tapMove(WidgetTester tester, Square from, Square to) async {
  final side = boardOrientation(tester);
  await tester.tapAt(squareOffset(tester, from, orientation: side));
  await tester.pump();
  await tester.tapAt(squareOffset(tester, to, orientation: side));
  await tester.pump();
}
