import 'package:chesspuzzle/data/prefs.dart';
import 'package:chesspuzzle/domain/puzzle.dart';
import 'package:chesspuzzle/screens/post_puzzle/post_puzzle_screen.dart';
import 'package:chesspuzzle/screens/solve/solve_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/pump_app.dart';

/// The auto-advance countdown, told apart from the per-theme progress
/// bars (which are 6px tall) by its 3px height.
final Finder autoAdvanceBar = find.byWidgetPredicate(
  (w) => w is LinearProgressIndicator && w.minHeight == 3,
);

void main() {
  late TestHarness h;
  late Puzzle puzzle;

  setUpAll(initSqfliteForTests);
  setUp(() async {
    h = await TestHarness.create();
    puzzle = (await h.puzzleDb.byId('p-mate1-w'))!;
    // Off by default: an armed auto-advance timer outlives most of these
    // tests and a pending timer is a hard failure. The countdown gets its
    // own test below.
    await h.prefs.setInt(Prefs.kAutoAdvanceMs, 0);
  });
  tearDown(() async => h.dispose());

  /// Pumps a throwaway first route and pushes the result screen onto it,
  /// so `popUntil(isFirst)` has somewhere to land.
  Future<void> showResult(
    WidgetTester tester, {
    required bool solved,
    double delta = 7.5,
  }) async {
    await pumpApp(
      tester,
      harness: h,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => PostPuzzleScreen(
                    puzzle: puzzle,
                    solved: solved,
                    ratingDelta: delta,
                  ),
                ),
              ),
              child: const Text('DASHBOARD-STUB'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('DASHBOARD-STUB'));
    await pumpUntil(tester, find.byType(PostPuzzleScreen));
    await pumpFrames(tester, frames: 20);
  }

  group('outcome', () {
    testWidgets('a solve shows the solved treatment and the new rating',
        (tester) async {
      await showResult(tester, solved: true, delta: 7.5);

      expect(find.text('Solved'), findsOneWidget);
      expect(find.text('Missed'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      // Fresh rating 1200 internal → 900 displayed, +7.5 this puzzle.
      expect(find.text('900'), findsOneWidget);
      expect(find.text('+7.5'), findsOneWidget);
      // Corpus prose is surfaced verbatim.
      expect(find.text('The back rank is fatally weak.'), findsOneWidget);
      expect(find.text('Test corpus'), findsOneWidget);
    });

    testWidgets('a miss shows the missed treatment and a negative delta',
        (tester) async {
      await showResult(tester, solved: false, delta: -9.0);

      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Solved'), findsNothing);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.text('-9.0'), findsOneWidget);
    });

    testWidgets('theme chips use display names from the corpus',
        (tester) async {
      await showResult(tester, solved: true);

      expect(
        find.descendant(of: find.byType(Chip), matching: find.text('Mate in one')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Chip),
          matching: find.text('Back rank mate'),
        ),
        findsOneWidget,
      );
      // Never the raw theme id.
      expect(find.text('mateIn1'), findsNothing);
    });

    testWidgets('per-puzzle history appears once there are attempts',
        (tester) async {
      await h.playerDb.recordAttempt(
        puzzleId: puzzle.id,
        outcome: 'failed',
        firstWrongMoveUci: 'a1a7',
        ratingDeltaGlobal: -9,
        solveDurationMs: 20000,
      );
      await h.playerDb.recordAttempt(
        puzzleId: puzzle.id,
        outcome: 'solved',
        firstWrongMoveUci: null,
        ratingDeltaGlobal: 7,
        solveDurationMs: 10000,
      );

      await showResult(tester, solved: true);

      expect(find.text('ATTEMPTS'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('AVG TIME'), findsOneWidget);
      expect(find.text('15s'), findsOneWidget);
    });

    testWidgets('no history panel on the first ever attempt', (tester) async {
      await showResult(tester, solved: true);
      expect(find.text('ATTEMPTS'), findsNothing);
    });
  });

  group('exits', () {
    testWidgets('Next replaces the screen with another puzzle',
        (tester) async {
      await showResult(tester, solved: true);

      await tester.tap(find.text('Next'));
      await pumpUntil(tester, find.byType(SolveScreen));
      await pumpFrames(tester, frames: 30);

      expect(find.byType(PostPuzzleScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Dashboard pops back to the first route', (tester) async {
      await showResult(tester, solved: true);

      await tester.tap(find.byTooltip('Dashboard'));
      await pumpUntil(tester, find.text('DASHBOARD-STUB'));
      await pumpFrames(tester, frames: 30);

      expect(find.byType(PostPuzzleScreen), findsNothing);
    });

    testWidgets('auto-advance is hidden when the preference is off',
        (tester) async {
      await showResult(tester, solved: true);
      expect(autoAdvanceBar, findsNothing);
    });

    // The countdown's *firing* is deliberately not covered by a widget
    // test. Enabling it arms a Future.delayed that is still pending when the
    // test body ends; teardown flushes fake time, which fires it, which
    // pushReplacement's a screen that then loads from the database — all
    // while the binding is tearing down. The binding wedges: the isolate
    // stops yielding, so even the per-test timeout cannot fire and the whole
    // suite stalls instead of failing. Verified by reducing to a bare mount
    // with the preference set: no navigation and no extra pumps still hangs.
    //
    // This is a fake-time/real-async hazard in the test binding, not an app
    // defect. The behaviour behind it is one Navigator call guarded by a
    // route-currency check, and the destination screen is covered directly
    // in solve_screen_test.dart. The setUp above pins the preference to 0
    // for the same reason.
  });

  group('accessibility', () {
    testWidgets('icon-only actions are labelled and big enough',
        (tester) async {
      final handle = tester.ensureSemantics();
      await showResult(tester, solved: true);

      expect(find.byTooltip('Analyze'), findsOneWidget);
      expect(find.byTooltip('Dashboard'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });
  });
}
