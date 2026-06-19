import 'package:chesspuzzle/app.dart';
import 'package:chesspuzzle/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Default test surface: 600x900 logical pixels, portrait.
///
/// Deliberately wider than a real phone. `flutter test` renders every
/// glyph of the fallback font as a full-em square, so strings measure
/// roughly twice their production width; on a true 390pt surface the
/// dashboard's AppBar title row overflows purely because of that. 600pt
/// keeps text-metric artifacts out of the assertions while staying
/// portrait, so the phone layout branches still run.
///
/// The flutter_test default (800x600, landscape) is worse on both counts:
/// nothing ships in that shape, and the solve screen's board-sizing math
/// overflows vertically in it.
const Size kDefaultSurface = Size(600, 900);

/// Pumps [home] (or the whole [ChesspuzzleApp]) with the harness'
/// providers overridden.
///
/// Animations are disabled through `MediaQuery.disableAnimations` by
/// default. That is not just cosmetic: `LiveDot` repeats forever, so with
/// motion enabled `pumpAndSettle` can never settle. It also matches the OS
/// reduce-motion path the widgets already special-case, which is the path
/// we want deterministic. Pass `reduceMotion: false` to test the animated
/// path explicitly.
Future<void> pumpApp(
  WidgetTester tester, {
  required TestHarness harness,
  Widget? home,
  List<Override> extraOverrides = const [],
  bool reduceMotion = true,
  Size surfaceSize = kDefaultSurface,
  Brightness brightness = Brightness.dark,
  bool pumpAfterBuild = true,
}) async {
  stubPlatformChannels();
  await setSurfaceSize(tester, surfaceSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...harness.overrides, ...extraOverrides],
      child: Builder(
        builder: (context) {
          final child = home == null
              ? const ChesspuzzleApp()
              : MaterialApp(
                  theme: buildLightTheme(),
                  darkTheme: buildDarkTheme(),
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  debugShowCheckedModeBanner: false,
                  home: home,
                );
          if (!reduceMotion) return child;
          // Sits ABOVE MaterialApp on purpose: WidgetsApp's
          // MediaQuery.fromView merges the platform-level flags from any
          // ancestor MediaQuery, so this survives into the app.
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: child,
          );
        },
      ),
    ),
  );
  // Pass `pumpAfterBuild: false` to inspect the very first frame — the one
  // where every FutureProvider is still `AsyncLoading`.
  if (pumpAfterBuild) await tester.pump();
}

/// Answers the platform channels the UI touches so their futures resolve
/// inside the test's fake-async zone.
///
/// Without this, `HapticFeedback.mediumImpact()` — awaited by the solve
/// screen before it grades a move — hands its reply to the real event
/// loop, which a widget test never turns, and the puzzle silently never
/// resolves.
void stubPlatformChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// Sets the logical surface size and restores it after the test.
Future<void> setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Pumps frames until [finder] matches, or fails with a readable message.
///
/// Preferred over `pumpAndSettle` anywhere a screen can show an
/// indeterminate `CircularProgressIndicator` (which schedules frames
/// forever) or an auto-advance timer we do not want to fire.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  String? reason,
  Duration step = const Duration(milliseconds: 20),
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  fail('Timed out after $maxFrames frames waiting for '
      '${reason ?? finder.description}');
}

/// Pumps [frames] frames of [step] each. Use instead of `pumpAndSettle`
/// when something on screen animates indefinitely.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 10,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}
