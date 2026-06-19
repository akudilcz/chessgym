import 'dart:io';

import 'package:chesspuzzle/data/puzzle_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Repo-integrity checks against the real shipped corpus.
///
/// These read `app/assets/puzzles/puzzles.sqlite` directly rather than a
/// fixture, because what they guard is a property of the artifact we ship.
void main() {
  const assetPath = 'assets/puzzles/puzzles.sqlite';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database?> openCorpus() async {
    final file = File(assetPath).absolute;
    if (!file.existsSync()) return null;
    // sqflite resolves a relative path against its own databases directory,
    // not the working directory, so the absolute path is required here.
    return databaseFactory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  }

  test('assetVersion matches corpus_meta.version in the shipped asset',
      () async {
    // The version marker is the ONLY trigger for re-copying the corpus onto
    // a device. If a rebuilt corpus ships without bumping the constant,
    // every existing install keeps the old puzzles permanently — silently.
    final db = await openCorpus();
    if (db == null) {
      markTestSkipped('corpus asset not present');
      return;
    }
    final rows = await db.rawQuery('SELECT version FROM corpus_meta');
    await db.close();

    expect(rows, hasLength(1));
    expect(
      rows.first['version'],
      PuzzleDb.assetVersion,
      reason: 'PuzzleDb.assetVersion and corpus_meta.version have drifted; '
          'bump PuzzleDb.assetVersion whenever puzzles.sqlite is rebuilt',
    );
  });

  test('famous studies keep their key move for the solver', () async {
    // Consuming a study's first move as a setup move plays Reti's Kg7,
    // Lasker's queen sacrifice and Saavedra's c8=R for the player, and
    // inverts the sides so the player defends. The pipeline no longer does
    // this; this guards the shipped rows against a stale rebuild.
    final db = await openCorpus();
    if (db == null) {
      markTestSkipped('corpus asset not present');
      return;
    }
    final rows = await db.rawQuery(
      "SELECT id, setup_move, moves_uci FROM puzzles "
      "WHERE origin_kind = 'famous' ORDER BY id",
    );
    await db.close();

    expect(rows, isNotEmpty, reason: 'no famous studies in the corpus');
    for (final row in rows) {
      expect(
        row['setup_move'],
        '',
        reason: '${row['id']} has a setup move invented from its solution '
            'line, so the study\'s key move is played for the player',
      );
      expect((row['moves_uci'] as String).trim(), isNotEmpty);
    }
  });
}
