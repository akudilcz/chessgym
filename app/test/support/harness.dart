import 'dart:io';

import 'package:chesspuzzle/data/player_db.dart';
import 'package:chesspuzzle/data/prefs.dart';
import 'package:chesspuzzle/data/providers.dart';
import 'package:chesspuzzle/data/puzzle_db.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// path_provider_platform_interface is a transitive dependency of
// path_provider. We take it on directly here (and only here) to redirect
// `getApplicationSupportDirectory` at a temp dir: `Prefs` has no
// constructor a test can reach, so stubbing the platform is the only way
// to keep prefs.txt out of the developer's real XDG data dir.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_corpus.dart';

/// Installs the SQLite implementation used by every test in this suite.
///
/// Widget tests run inside `FakeAsync`; the default [databaseFactoryFfi]
/// talks to a background isolate whose replies are delivered by the *real*
/// event loop, which a widget test never turns unless you wrap every
/// interaction in `tester.runAsync`. The no-isolate factory does the same
/// SQLite work synchronously on this isolate and completes its futures via
/// microtasks, which `tester.pump()` flushes — so real DB reads resolve
/// mid-test. Pure-Dart (non-widget) tests can use either.
void initSqfliteForTests() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// A fully wired, disposable stack of real objects over temp files:
/// a corpus sqlite, a `PuzzleDb`, a `PlayerDb`, and a `Prefs` rooted in the
/// same temp dir.
///
/// Nothing here is a mock — the tests drive the same SQL, the same
/// migrations and the same services the app runs in production. Only the
/// *paths* are test-owned.
///
/// ```dart
/// late TestHarness h;
/// setUp(() async => h = await TestHarness.create());
/// tearDown(() async => h.dispose());
///
/// testWidgets('...', (tester) async {
///   await pumpApp(tester, harness: h, home: const MapScreen());
/// });
/// ```
class TestHarness {
  final Directory dir;
  final String corpusPath;
  final PuzzleDb puzzleDb;
  final PlayerDb playerDb;
  final Prefs prefs;

  TestHarness._({
    required this.dir,
    required this.corpusPath,
    required this.puzzleDb,
    required this.playerDb,
    required this.prefs,
  });

  /// Build a corpus, open both databases over temp files and point
  /// `path_provider` (and therefore [Prefs]) at the same temp dir.
  ///
  /// Call from `setUp`, never from inside `testWidgets` — the file I/O
  /// here needs the real event loop.
  static Future<TestHarness> create({
    List<TestPuzzle> puzzles = kTestPuzzles,
    List<TestTheme> themes = kTestThemes,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // One root per test file (i.e. per isolate), one subdir per test.
    // `Prefs` is a process-wide singleton that latches onto the first
    // support directory it sees and never lets go, so the root has to
    // outlive individual tests — see [resetPrefs].
    final root = _suiteRoot ??= Directory.systemTemp
        .createTempSync('chessgym_test_')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final dir = Directory(p.join(root.path, 'case_${_caseCounter++}'))
      ..createSync(recursive: true);

    final corpusPath = p.join(dir.path, 'puzzles.sqlite');
    await buildTestCorpus(corpusPath, puzzles: puzzles, themes: themes);

    final puzzleDb = await PuzzleDb.openAt(corpusPath);
    final playerDb = await PlayerDb.open(
      puzzlesDbPath: corpusPath,
      playerDbPath: p.join(dir.path, 'player.sqlite'),
    );
    final prefs = await Prefs.instance();
    final harness = TestHarness._(
      dir: dir,
      corpusPath: corpusPath,
      puzzleDb: puzzleDb,
      playerDb: playerDb,
      prefs: prefs,
    );
    await harness.resetPrefs();
    return harness;
  }

  static Directory? _suiteRoot;
  static int _caseCounter = 0;

  /// Rewrites every known preference to its documented default.
  ///
  /// [Prefs] caches itself in a static and exposes no reset, so without
  /// this a value written by one test would leak into the next.
  Future<void> resetPrefs() async {
    await prefs.setBool(Prefs.kHapticsOn, true);
    await prefs.setInt(Prefs.kAutoAdvanceMs, 10400);
    await prefs.setBool(Prefs.kOnboardingSeen, false);
  }

  /// Riverpod overrides that swap the temp-file databases in for the
  /// asset-backed / app-support-backed real ones.
  ///
  /// Returned synchronously-resolved so the widgets under test never see a
  /// `AsyncLoading` frame for the databases themselves; derived providers
  /// (`journeyProvider`, …) still resolve asynchronously, exactly as in
  /// production.
  List<Override> get overrides => [
        puzzleDbProvider.overrideWith((ref) => puzzleDb),
        playerDbProvider.overrideWith((ref) => playerDb),
        prefsProvider.overrideWith((ref) => prefs),
      ];

  /// Closes both databases and deletes the temp dir. Safe to call twice.
  Future<void> dispose() async {
    try {
      await puzzleDb.close();
    } catch (_) {/* already closed */}
    try {
      await playerDb.close();
    } catch (_) {/* already closed */}
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
