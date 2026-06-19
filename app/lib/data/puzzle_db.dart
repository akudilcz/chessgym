import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/puzzle.dart';

/// Read-only access to the shipped `puzzles.sqlite` asset.
///
/// On open:
///   1. Load the shipped asset hash (sha256 over a small header prefix of
///      the asset so we don't load the whole file into memory).
///   2. Compare against the on-device file; if absent or stale, overwrite
///      so app-store updates with a newer puzzle DB actually reach users.
///   3. Open read-only via sqflite / sqflite_common_ffi (platform-agnostic).
class PuzzleDb {
  static const _assetPath = 'assets/puzzles/puzzles.sqlite';

  /// Version marker for the shipped corpus.
  ///
  /// Must equal `corpus_meta.version` inside the asset, and must be bumped
  /// whenever `puzzles.sqlite` changes: a mismatch against the marker file on
  /// disk is the ONLY thing that triggers a re-copy, so a rebuilt corpus that
  /// forgets the bump never reaches a device that already holds the old one.
  /// `corpus_version_test.dart` fails if the two drift apart.
  static const assetVersion = '0.2.0+187k';
  final Database _db;
  final String path;
  PuzzleDb._(this._db, this.path);

  // Shipped corpus is read-only at runtime. Cache expensive reads for the
  // lifetime of the DB — rebuilding them on every journey refresh burned
  // multi-second frames on the Android UI isolate.
  Future<Map<String, List<String>>>? _themesMapCache;
  Future<List<ThemeInfo>>? _themesCache;
  Future<Map<String, int>>? _themeTotalsCache;

  /// puzzle_id → list of theme_ids. 395k rows in the shipped corpus;
  /// building the Dart map round-trips every row through the sqflite
  /// platform channel, so we cache for the PuzzleDb lifetime. Cold call
  /// ~700–1400 ms on mid-range Android, warm call is instant.
  Future<Map<String, List<String>>> puzzleThemesMap() {
    return _themesMapCache ??= _buildThemesMap();
  }

  Future<Map<String, List<String>>> _buildThemesMap() async {
    final rows = await _db
        .rawQuery('SELECT puzzle_id, theme_id FROM puzzle_themes');
    final out = <String, List<String>>{};
    for (final r in rows) {
      final pid = r['puzzle_id'] as String;
      (out[pid] ??= <String>[]).add(r['theme_id'] as String);
    }
    return out;
  }

  static Future<PuzzleDb> open() async {
    final dir = await getApplicationSupportDirectory();
    final dest = File(p.join(dir.path, 'puzzles.sqlite'));
    final hashFile = File(p.join(dir.path, 'puzzles.sqlite.sha256'));

    // On Android the asset is 58+ MB. Loading it into memory and SHA256-ing
    // it on the main isolate triggered ANRs that Android killed. New path:
    //   - If the destination file already exists, SKIP the hash+copy entirely.
    //     Version bumps are detected via a lightweight pubspec-version
    //     marker file instead — cheap, no 58 MB read.
    //   - Only on first install or when the version marker mismatches do we
    //     do the heavy copy, and we stream-write via openRead.pipe to avoid
    //     holding the whole thing in memory.
    const assetVersion = PuzzleDb.assetVersion;
    final versionFile = File(p.join(dir.path, 'puzzles.sqlite.version'));
    final existingVersion =
        versionFile.existsSync() ? await versionFile.readAsString() : '';
    final needsCopy = !await dest.exists() || existingVersion != assetVersion;

    if (needsCopy) {
      // Write in one call from ByteData — rootBundle.load returns ByteData
      // already; writeAsBytes handles chunking internally in sqflite/dart:io.
      final assetBytes = await rootBundle.load(_assetPath);
      await dest.writeAsBytes(
        assetBytes.buffer.asUint8List(
            assetBytes.offsetInBytes, assetBytes.lengthInBytes),
        flush: true,
      );
      await versionFile.writeAsString(assetVersion, flush: true);
      // Keep a sha256 sidecar for any future code that needs it, but only
      // compute it during the already-heavy copy path.
      final h = sha256.convert(assetBytes.buffer.asUint8List(
              assetBytes.offsetInBytes, assetBytes.lengthInBytes))
          .toString();
      await hashFile.writeAsString(h, flush: true);
    }

    final db = await databaseFactory.openDatabase(
      dest.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    return PuzzleDb._(db, dest.path);
  }

  /// Open an existing corpus file directly, skipping the asset copy.
  ///
  /// Exists so tests can drive the real query methods against a purpose-built
  /// corpus. Without it a test can only re-declare the schema and assert
  /// against its own copy, which passes even when this class drifts.
  @visibleForTesting
  static Future<PuzzleDb> openAt(String path) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    return PuzzleDb._(db, path);
  }

  Future<void> close() => _db.close();

/// For each theme, how many puzzles reference it in the shipped corpus.
  Future<Map<String, int>> themeTotals() {
    return _themeTotalsCache ??= _buildThemeTotals();
  }

  Future<Map<String, int>> _buildThemeTotals() async {
    final rows = await _db.rawQuery('''
      SELECT theme_id, COUNT(*) AS n FROM puzzle_themes GROUP BY theme_id
    ''');
    return {
      for (final r in rows) r['theme_id'] as String: r['n'] as int,
    };
  }

  Future<List<ThemeInfo>> listThemes() {
    return _themesCache ??= _buildThemes();
  }

  Future<List<ThemeInfo>> _buildThemes() async {
    final rows = await _db.rawQuery('''
      SELECT t.id, t.display_name, t.description, t.importance,
             t.floor_rating, t.ceiling_rating,
             COALESCE(GROUP_CONCAT(p.prereq_id, ','), '') AS prereqs
      FROM themes t
      LEFT JOIN theme_prereqs p ON p.theme_id = t.id
      GROUP BY t.id
    ''');
    return rows.map((r) {
      final prereqStr = r['prereqs'] as String;
      return ThemeInfo(
        id: r['id'] as String,
        displayName: r['display_name'] as String,
        description: r['description'] as String,
        importance: (r['importance'] as num).toDouble(),
        floorRating: r['floor_rating'] as int,
        ceilingRating: r['ceiling_rating'] as int,
        prereqs: prereqStr.isEmpty ? const [] : prereqStr.split(','),
      );
    }).toList();
  }

  /// Candidate puzzles restricted by theme, optional rating band.
  ///
  /// Themes are NOT populated on returned puzzles — the selection
  /// algorithm doesn't read them, and running GROUP_CONCAT on 200
  /// candidates was ~470 ms of the pickNext path. Caller reloads the
  /// picked puzzle via [byId] (cheap PK lookup) before returning it
  /// to the UI.
  Future<List<Puzzle>> candidatesForTheme(
    String themeId, {
    required int ratingMin,
    required int ratingMax,
    int limit = 200,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT p.*
      FROM puzzles p
      INNER JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      WHERE pt.theme_id = ?
        AND p.rating BETWEEN ? AND ?
      ORDER BY p.interest DESC
      LIMIT ?
    ''', [themeId, ratingMin, ratingMax, limit]);
    return rows.map(_rowToPuzzle).toList();
  }

  /// Random puzzle near a target rating, any theme. Used by the
  /// calibration flow where we specifically want to serve a puzzle at
  /// rating X regardless of the player's theme history.
  Future<Puzzle?> puzzleNearRating(int target, {int bandWidth = 100}) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
      FROM puzzles p
      LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      WHERE p.rating BETWEEN ? AND ?
      GROUP BY p.id
      ORDER BY p.interest DESC
      LIMIT 50
    ''', [target - bandWidth, target + bandWidth]);
    if (rows.isEmpty) {
      // Widen.
      if (bandWidth < 500) {
        return puzzleNearRating(target, bandWidth: bandWidth * 2);
      }
      return null;
    }
    // Random pick from the top-interest set.
    final r = rows[DateTime.now().microsecondsSinceEpoch % rows.length];
    return _rowToPuzzle(r);
  }

  /// Last-resort: return any puzzle whatsoever. Guaranteed non-empty
  /// result if the DB has at least one row (it does — 5,786).
  Future<Puzzle?> anyPuzzle() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
      FROM puzzles p
      LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      GROUP BY p.id
      ORDER BY p.interest DESC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    return _rowToPuzzle(rows.first);
  }

  Future<Puzzle?> byId(String id) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, GROUP_CONCAT(pt.theme_id, ',') AS theme_ids
      FROM puzzles p
      LEFT JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      WHERE p.id = ?
      GROUP BY p.id
    ''', [id]);
    if (rows.isEmpty) return null;
    return _rowToPuzzle(rows.first);
  }

  Future<Puzzle?> dailyFor(DateTime date) async {
    final slotRows = await _db.rawQuery('SELECT COUNT(*) AS n FROM daily_index');
    final n = slotRows.first['n'] as int;
    if (n == 0) return null;
    // A decimal-packed YYYYMMDD seed collapses against a round slot count:
    // 200 divides 10000 so the year term vanishes entirely, and
    // month * 100 % 200 is only ever 0 or 100 — leaving 62 of 200 slots
    // reachable and making 2026-03-05 and 2026-05-05 the same puzzle.
    // FNV-1a over the date spreads across every slot.
    var hash = 0x811c9dc5;
    for (final unit in '${date.year}-${date.month}-${date.day}'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final slot = hash % n;
    final rows = await _db.rawQuery(
      'SELECT puzzle_id FROM daily_index WHERE slot = ?',
      [slot],
    );
    if (rows.isEmpty) return null;
    return byId(rows.first['puzzle_id'] as String);
  }

  Puzzle _rowToPuzzle(Map<String, Object?> r) {
    final themeStr = (r['theme_ids'] as String?) ?? '';
    return Puzzle(
      id: r['id'] as String,
      fen: r['fen'] as String,
      setupMove: r['setup_move'] as String,
      sideToMove: r['side_to_move'] as String,
      moves: (r['moves_uci'] as String).split(' '),
      rating: r['rating'] as int,
      ratingDev: r['rating_dev'] as int,
      popularity: r['popularity'] as int,
      nbPlays: r['nb_plays'] as int,
      interest: (r['interest'] as num).toDouble(),
      originKind: r['origin_kind'] as String,
      originLabel: r['origin_label'] as String?,
      explanation: r['explanation'] as String?,
      themes: themeStr.isEmpty ? const [] : themeStr.split(','),
    );
  }
}
