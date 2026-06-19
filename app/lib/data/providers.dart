import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/puzzle.dart';
// ignore: unused_import
import 'player_db.dart';
import 'prefs.dart';
import 'progress_service.dart';
import 'puzzle_db.dart';
import 'selection_service.dart';

final prefsProvider = FutureProvider<Prefs>((ref) async {
  return Prefs.instance();
});

final puzzleDbProvider = FutureProvider<PuzzleDb>((ref) async {
  final db = await PuzzleDb.open();
  ref.onDispose(db.close);
  return db;
});

final playerDbProvider = FutureProvider<PlayerDb>((ref) async {
  // PlayerDb ATTACHes the puzzles DB to run aggregation JOINs
  // server-side, so it needs the puzzles DB on disk first.
  final pz = await ref.watch(puzzleDbProvider.future);
  final db = await PlayerDb.open(puzzlesDbPath: pz.path);
  ref.onDispose(db.close);
  return db;
});

final themesProvider = FutureProvider<List<ThemeInfo>>((ref) async {
  final db = await ref.watch(puzzleDbProvider.future);
  return db.listThemes();
});

final globalRatingProvider = FutureProvider<Glicko2>((ref) async {
  final pdb = await ref.watch(playerDbProvider.future);
  return pdb.globalRating();
});

final selectionServiceProvider = FutureProvider<SelectionService>((ref) async {
  final pzDb = await ref.watch(puzzleDbProvider.future);
  final plDb = await ref.watch(playerDbProvider.future);
  return SelectionService(pzDb, plDb);
});

final progressServiceProvider = FutureProvider<ProgressService>((ref) async {
  final pzDb = await ref.watch(puzzleDbProvider.future);
  final plDb = await ref.watch(playerDbProvider.future);
  return ProgressService(pzDb, plDb);
});

/// Full journey snapshot. Recomputed on demand; callers `ref.invalidate` after
/// a puzzle is resolved to refresh.
final journeyProvider = FutureProvider<JourneySnapshot>((ref) async {
  final svc = await ref.watch(progressServiceProvider.future);
  return svc.snapshot();
});

final nextPuzzleProvider = FutureProvider.family<Puzzle?, String?>(
  (ref, themeId) async {
    final svc = await ref.watch(selectionServiceProvider.future);
    // Share the dashboard's journey snapshot rather than letting pickNext
    // recompute it: the snapshot is expensive and runs on the UI isolate.
    final snap = await ref.watch(journeyProvider.future);
    return svc.pickNext(
      themeFocus: themeId,
      now: DateTime.now(),
      snapshot: snap,
    );
  },
);

/// Deterministic daily puzzle for today's date.
final dailyPuzzleProvider = FutureProvider<Puzzle?>((ref) async {
  final db = await ref.watch(puzzleDbProvider.future);
  final now = DateTime.now();
  final date = DateTime.utc(now.year, now.month, now.day);
  return db.dailyFor(date);
});
