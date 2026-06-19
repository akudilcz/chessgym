import 'package:chesspuzzle/data/prefs.dart';
import 'package:chesspuzzle/screens/post_puzzle/post_puzzle_screen.dart';
import 'package:chesspuzzle/screens/solve/solve_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/board.dart';
import '../support/harness.dart';
import '../support/pump_app.dart';

/// Timings copied from `_SolveScreenState`: the screen deliberately holds
/// the board on screen after the last move so the player sees it before
/// the result screen replaces it.
const _afterCorrect = Duration(milliseconds: 220 + 100 + 50);
const _afterWrong = Duration(milliseconds: 220 + 500 + 50);
const _giveUpAfter = Duration(seconds: 31);

void main() {
  late TestHarness h;

  setUpAll(initSqfliteForTests);
  setUp(() async {
    h = await TestHarness.create();
    // Kill the post-puzzle auto-advance timer: a pending 10.4 s timer at
    // the end of a widget test is a hard failure, and nothing here is
    // testing the countdown.
    await h.prefs.setInt(Prefs.kAutoAdvanceMs, 0);
  });
  tearDown(() async => h.dispose());

  Future<void> openPuzzle(WidgetTester tester, String id) async {
    await pumpApp(
      tester,
      harness: h,
      home: SolveScreen(specificPuzzleId: id),
    );
    await pumpUntil(tester, boardFinder, reason: 'the board to load');
  }

  group('board rendering', () {
    testWidgets('renders the puzzle position and whose move it is',
        (tester) async {
      await openPuzzle(tester, 'p-mate1-w');

      expect(boardFinder, findsOneWidget);
      expect(find.text('White to move'), findsOneWidget);
      // Every piece of the seeded back-rank position, on its own square.
      for (final key in const [
        'a1-whiterook',
        'g1-whiteking',
        'f2-whitepawn',
        'g2-whitepawn',
        'h2-whitepawn',
        'g8-blackking',
        'f7-blackpawn',
        'g7-blackpawn',
        'h7-blackpawn',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      // Difficulty badge: rating 1200 → D4 (see difficulty1to10).
      expect(find.text('D4'), findsOneWidget);
    });

    testWidgets('black-to-move puzzle announces black and flips the board',
        (tester) async {
      await openPuzzle(tester, 'p-mate1-b');

      expect(find.text('Black to move'), findsOneWidget);
      expect(boardOrientation(tester), Side.black);
    });

    testWidgets('setup_move is replayed before the player gets control',
        (tester) async {
      // p-setupmove's FEN has the king on g8 and a setup move Kg8-h8.
      await openPuzzle(tester, 'p-setupmove');

      expect(find.byKey(const ValueKey('h8-blackking')), findsOneWidget);
      expect(find.byKey(const ValueKey('g8-blackking')), findsNothing);
      expect(find.text('White to move'), findsOneWidget);
    });
  });

  group('grading a move', () {
    testWidgets('a correct move ends the puzzle as Solved', (tester) async {
      await openPuzzle(tester, 'p-mate1-w');

      await tapMove(tester, Square.a1, Square.a8);
      await tester.pump(_afterCorrect);
      await pumpUntil(tester, find.byType(PostPuzzleScreen));

      expect(find.text('Solved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // The attempt reached the database, not just the screen.
      final stats = await h.playerDb.puzzleStats('p-mate1-w');
      expect(stats?.solves, 1);
      expect(stats?.fails, 0);
    });

    testWidgets('a wrong move ends the puzzle as Missed and records it',
        (tester) async {
      await openPuzzle(tester, 'p-mate1-w');

      // Ra1-a7 is legal but does not mate.
      await tapMove(tester, Square.a1, Square.a7);
      await tester.pump(_afterWrong);
      await pumpUntil(tester, find.byType(PostPuzzleScreen));

      expect(find.text('Missed'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

      final stats = await h.playerDb.puzzleStats('p-mate1-w');
      expect(stats?.fails, 1);
      expect(stats?.solves, 0);
      // The wrong move is stored for the analyze screen.
      final rows = await h.playerDb.missedPuzzleIds();
      expect(rows, contains('p-mate1-w'));
    });

    testWidgets('an illegal drag is refused by the board, not graded',
        (tester) async {
      await openPuzzle(tester, 'p-mate1-w');

      // Rook a1 cannot reach b3. chessground never emits onMove, so the
      // puzzle must still be in progress.
      await tapMove(tester, Square.a1, Square.b3);
      await tester.pump(_afterWrong);

      expect(find.byType(PostPuzzleScreen), findsNothing);
      expect(boardFinder, findsOneWidget);
      final stats = await h.playerDb.puzzleStats('p-mate1-w');
      expect(stats?.attempts ?? 0, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('multi-move puzzle plays the scripted reply and waits',
        (tester) async {
      await openPuzzle(tester, 'p-threeply');

      // Ply 1: Ra1-a8+ — correct, but the puzzle continues.
      await tapMove(tester, Square.a1, Square.a8);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PostPuzzleScreen), findsNothing);
      // Scripted reply Kg8-h7 has been applied for the player to see.
      expect(find.byKey(const ValueKey('h7-blackking')), findsOneWidget);

      // Ply 3: Ra8-a7 finishes it.
      await tapMove(tester, Square.a8, Square.a7);
      await tester.pump(_afterCorrect);
      await pumpUntil(tester, find.byType(PostPuzzleScreen));

      expect(find.text('Solved'), findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('restart puts the pieces back without leaving the screen',
        (tester) async {
      await openPuzzle(tester, 'p-threeply');

      await tapMove(tester, Square.a1, Square.a8);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('a8-whiterook')), findsOneWidget);

      await tester.tap(find.byTooltip('Restart puzzle'));
      await pumpFrames(tester, frames: 20);

      expect(find.byKey(const ValueKey('a1-whiterook')), findsOneWidget);
      expect(find.byKey(const ValueKey('g8-blackking')), findsOneWidget);
      expect(find.byType(PostPuzzleScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Give up appears only after the idle window and fails the '
        'puzzle', (tester) async {
      await openPuzzle(tester, 'p-mate1-w');

      // Hidden (fully transparent) before the window elapses.
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Give up'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);

      await tester.pump(_giveUpAfter);
      await pumpFrames(tester, frames: 20);
      final shown = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Give up'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(shown.opacity, 1.0);

      await tester.tap(find.text('Give up'));
      await pumpUntil(tester, find.byType(PostPuzzleScreen));

      expect(find.text('Missed'), findsOneWidget);
      final stats = await h.playerDb.puzzleStats('p-mate1-w');
      expect(stats?.fails, 1);
    });
  });

  group('accessibility', () {
    testWidgets('the board announces the position to a screen reader',
        (tester) async {
      // chessground contributes no semantics of its own, so without an
      // explicit label the board is a blank region — the single largest
      // gap against specs/accessibility.md.
      final handle = tester.ensureSemantics();
      await openPuzzle(tester, 'p-mate1-w');

      final labels = <String>[];
      void walk(SemanticsNode node) {
        if (node.label.isNotEmpty) labels.add(node.label);
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      final board = labels.where((l) => l.contains('to move.'));
      expect(board, isNotEmpty,
          reason: 'the board exposed no semantics label at all');
      // It should name pieces and squares, not just whose turn it is.
      expect(board.first, contains('king'));
      expect(board.first, matches(RegExp(r'[a-h][1-8]')));

      handle.dispose();
    });

    testWidgets('app-bar controls are labelled and meet tap-target minimums',
        (tester) async {
      final handle = tester.ensureSemantics();
      await openPuzzle(tester, 'p-mate1-w');

      // specs/accessibility.md: every control is reachable by a screen
      // reader…
      for (final tooltip in ['Dashboard', 'Restart puzzle']) {
        expect(find.byTooltip(tooltip), findsOneWidget,
            reason: '$tooltip button should expose a semantics label');
        expect(
          tester.getSemantics(find.byTooltip(tooltip)),
          matchesSemantics(
            // IconButton exposes its tooltip as the announced string;
            // there is no separate semantics label.
            tooltip: tooltip,
            isButton: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasEnabledState: true,
            hasFocusAction: true,
          ),
        );
      }
      // …and hits the 48x48 dp / 44x44 pt minimums.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });
  });
}
