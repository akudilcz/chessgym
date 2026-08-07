import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/prefs.dart';
import 'data/providers.dart';
import 'screens/map/map_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/version_flash.dart';

class ChesspuzzleApp extends ConsumerWidget {
  const ChesspuzzleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Chess Gym',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      // Wraps the whole app, not a single screen, so the badge is
      // visible whichever screen the launch lands on.
      home: const VersionFlash(child: _Root()),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Chooses between the first-run intro and the dashboard.
///
/// [OnboardingScreen] existed but was never instantiated and
/// [Prefs.kOnboardingSeen] was never read, so the intro could not appear at
/// all. The preference is read once here; every later launch goes straight
/// to the dashboard.
class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  bool? _needsOnboarding;

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(prefsProvider);
    return prefsAsync.when(
      // Preferences live in a small local file, so this resolves within a
      // frame or two. Showing the dashboard scaffold rather than a spinner
      // avoids a flash of loading UI on every cold start.
      loading: () => const Scaffold(body: SizedBox.shrink()),
      // A preferences read failure must not lock the player out of the app;
      // fall through to the dashboard and let them play.
      error: (_, _) => const MapScreen(),
      data: (prefs) {
        final seen = _needsOnboarding == null
            ? prefs.getBool(Prefs.kOnboardingSeen, defaultValue: false)
            : !_needsOnboarding!;
        if (seen) return const MapScreen();
        return OnboardingScreen(
          prefs: prefs,
          onDone: () => setState(() => _needsOnboarding = false),
        );
      },
    );
  }
}
