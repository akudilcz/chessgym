/// Single source of truth for the app's human-readable version.
///
/// Must match `version:` in `app/pubspec.yaml` (the numeric part — the
/// `+N` build number suffix is Android versionCode / iOS CFBundleVersion
/// and is not displayed).
class AppInfo {
  static const version = '0.2.0';
  static const name = 'Chess Gym';

  /// Short legalese line shown on the built-in Flutter license page.
  static const legalese =
      'App code GPL-3.0. Puzzle data CC0 (Lichess). '
      'Piece set CC-BY-SA 3.0 (Colin M.L. Burnett).';
}
