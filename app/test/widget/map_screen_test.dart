import 'package:chesspuzzle/screens/map/map_screen.dart';
import 'package:chesspuzzle/screens/settings/settings_screen.dart';
import 'package:chesspuzzle/screens/solve/solve_screen.dart';
import 'package:chesspuzzle/widgets/animated_number.dart';
import 'package:chesspuzzle/widgets/tier_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/board.dart';
import '../support/harness.dart';
import '../support/pump_app.dart';

/// Reads the number rendered inside the HUD stat tile labelled [label].
///
/// The tile is a Column of `[Row(dot, label)], [value]`, so the value is
/// the one Text in that subtree that isn't the label itself.
String tileValue(WidgetTester tester, String label) {
  final tile = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      .where((t) => t != label)
      .toList();
  expect(texts, hasLength(1), reason: 'one value Text inside tile "$label"');
  return texts.single;
}

void main() {
  late TestHarness h;

  setUpAll(initSqfliteForTests);
  setUp(() async => h = await TestHarness.create());
  tearDown(() async => h.dispose());

  /// Pumps the dashboard and waits for the snapshot AND the FAB's entrance
  /// scale to finish — until it does, PLAY has a zero-size hit box.
  Future<void> openDashboard(WidgetTester tester) async {
    await pumpApp(tester, harness: h, home: const MapScreen());
    await pumpUntil(tester, find.text('PLAY'));
    await pumpFrames(tester, frames: 20);
  }

  group('dashboard', () {
    testWidgets('shows the loading HUD until the snapshot resolves',
        (tester) async {
      await pumpApp(
        tester,
        harness: h,
        home: const MapScreen(),
        pumpAfterBuild: false,
      );

      expect(find.text('Warming up the puzzle library…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No PLAY button while loading — nothing to play yet.
      expect(find.text('PLAY'), findsNothing);

      await pumpUntil(tester, find.text('PLAY'));
      expect(find.text('Warming up the puzzle library…'), findsNothing);
    });

    testWidgets('renders the HUD from a fresh player over the real corpus',
        (tester) async {
      await openDashboard(tester);

      // Fresh PlayerDb: internal 1200 → displayed 900 → NOVICE tier.
      expect(
        find.descendant(
          of: find.byType(AnimatedNumber),
          matching: find.text('900'),
        ),
        findsOneWidget,
      );
      expect(find.text('NOVICE'), findsOneWidget);
      expect(find.text('±350'), findsOneWidget);
      // The tier bar marks the same rating on the rainbow scale.
      expect(
        find.descendant(of: find.byType(TierBar), matching: find.text('900')),
        findsOneWidget,
      );

      expect(tileValue(tester, 'SOLVED'), '0');
      expect(tileValue(tester, 'ACCURACY'), '0%');
      expect(tileValue(tester, 'MISSED'), '0');
      expect(tileValue(tester, 'LEVEL'), '0');
      expect(find.text('L0'), findsOneWidget);
    });

    testWidgets('sorts every untouched theme into UNEXPLORED', (tester) async {
      await openDashboard(tester);

      expect(find.text('UNEXPLORED'), findsOneWidget);
      expect(find.text('TOP 5'), findsOneWidget);
      expect(find.text('PRACTICE'), findsOneWidget);
      // Nothing practised yet, so nothing can be fading or mastered.
      expect(find.text('REVIEW'), findsNothing);
      expect(find.text('MASTERED'), findsNothing);

      // Theme display names come from the corpus, upper-cased by the row.
      expect(find.text('MATE IN ONE'), findsWidgets);
      expect(find.text('BACK RANK MATE'), findsWidgets);
      // Never-attempted themes show an em-dash instead of a success rate.
      expect(find.text(' — '), findsWidgets);
    });

    testWidgets('reflects a recorded solve in the counters', (tester) async {
      await h.playerDb.recordAttempt(
        puzzleId: 'p-mate1-w',
        outcome: 'solved',
        firstWrongMoveUci: null,
        ratingDeltaGlobal: 7.5,
        solveDurationMs: 4000,
      );

      await openDashboard(tester);

      expect(tileValue(tester, 'SOLVED'), '1');
      expect(tileValue(tester, 'ACCURACY'), '100%');
      expect(tileValue(tester, 'MISSED'), '0');
      // 1 attempt + 5 per solve = 6 XP, still level 0 (level 1 needs 10).
      expect(find.text('6 / 10'), findsOneWidget);
    });

    testWidgets('counts an unresolved failure as MISSED', (tester) async {
      await h.playerDb.recordAttempt(
        puzzleId: 'p-mate1-w',
        outcome: 'failed',
        firstWrongMoveUci: 'a1a7',
        ratingDeltaGlobal: -9.0,
        solveDurationMs: 3000,
      );

      await openDashboard(tester);

      expect(tileValue(tester, 'MISSED'), '1');
      expect(tileValue(tester, 'SOLVED'), '0');
      expect(tileValue(tester, 'ACCURACY'), '0%');
    });
  });

  group('navigation', () {
    testWidgets('PLAY opens the solve screen with a real puzzle',
        (tester) async {
      await openDashboard(tester);

      await tester.tap(find.text('PLAY'));
      await pumpUntil(tester, find.byType(SolveScreen));
      await pumpUntil(tester, boardFinder, reason: 'the board to load');

      // A fresh player is un-calibrated, so selection serves a puzzle at
      // the 1200 calibration target — p-mate1-w is the only one in band.
      expect(find.text('White to move'), findsOneWidget);
      expectPiece(tester, 'a1-whiterook');
      expect(find.text('D4'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the settings action opens Settings', (tester) async {
      await openDashboard(tester);

      await tester.tap(find.byTooltip('Settings'));
      await pumpUntil(tester, find.byType(SettingsScreen));

      expect(find.text('SETTINGS'), findsOneWidget);
    });

    testWidgets('tapping the rating opens its explainer and closes again',
        (tester) async {
      await openDashboard(tester);

      await tester.tap(find.descendant(
        of: find.byType(AnimatedNumber),
        matching: find.text('900'),
      ));
      await pumpUntil(tester, find.byType(AlertDialog));

      expect(find.text('RATING'), findsOneWidget);
      expect(find.textContaining('Glicko-2'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await pumpFrames(tester, frames: 20);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('each stat tile explains itself on tap', (tester) async {
      await openDashboard(tester);

      await tester.tap(find.text('MISSED'));
      await pumpUntil(tester, find.byType(AlertDialog));

      expect(find.textContaining('resurface until cleared'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, frames: 20);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('dashboard controls meet the tap-target guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await openDashboard(tester);

      expect(find.byTooltip('Settings'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      // Every text on the HUD is reachable by a screen reader.
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('the pulsing HUD dot goes static under reduce-motion',
        (tester) async {
      await openDashboard(tester);
      // specs/accessibility.md: "pulse/glow affordances are replaced with
      // static outlines". Under reduceMotion LiveDot must not animate.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    });
  });
}
