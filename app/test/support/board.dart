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

/// True when the board currently shows [square] as selected.
bool isSelected(Square square) =>
    find.byKey(ValueKey('${square.name}-selected')).evaluate().isNotEmpty;
