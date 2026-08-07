/// Single source of truth for the app's human-readable version.
///
/// Must match `version:` in `app/pubspec.yaml` (the numeric part — the
/// `+N` build number suffix is Android versionCode / iOS CFBundleVersion
/// and is not displayed).
class AppInfo {
  static const version = '0.2.0';
  static const name = 'Chess Gym';

  /// CI build number, injected at compile time with
  /// `--dart-define=BUILD_NUMBER=…` (the GitHub Actions run number, which
  /// is also the Android versionCode and the number in the release title).
  ///
  /// Without it every build reports the same version string, so there is no
  /// way to tell from inside the app which APK is actually installed —
  /// exactly the question that matters when a download turns out to be
  /// stale. Local builds show `dev`.
  static const build = String.fromEnvironment(
    'BUILD_NUMBER',
    defaultValue: 'dev',
  );

  /// e.g. `0.2.0 (build 7)`.
  static const fullVersion = '$version (build $build)';

  /// Short legalese line shown on the built-in Flutter license page.
  static const legalese =
      'App code GPL-3.0. Puzzle data CC0 (Lichess). '
      'Piece set CC-BY-SA 3.0 (Colin M.L. Burnett).';
}
