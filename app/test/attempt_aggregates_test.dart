import 'package:flutter_test/flutter_test.dart';

import 'package:chesspuzzle/data/player_db.dart';

Map<String, Object?> row(String pid, String outcome, String resolvedAt) => {
      'puzzle_id': pid,
      'outcome': outcome,
      'resolved_at': resolvedAt,
    };

void main() {
  group('AttemptAggregates.fromRows', () {
    final themes = {
      'p1': ['fork', 'discovered'],
      'p2': ['fork'],
      'p3': ['endgame'],
    };

    test('counts solved / attempted distinct puzzle_ids per theme', () {
      // Two attempts on p1 — one failed then one solved — shouldn't double
      // count attempted OR solved for "fork" or "discovered".
      final rows = [
        row('p1', 'solved', '2026-04-20T10:00:00Z'),
        row('p1', 'failed', '2026-04-18T10:00:00Z'),
        row('p2', 'failed', '2026-04-19T10:00:00Z'),
        row('p3', 'solved', '2026-04-17T10:00:00Z'),
      ];
      final agg = AttemptAggregates.fromRows(
        rows,
        themesByPuzzle: themes,
        recentWindowPerTheme: 10,
      );
      expect(agg.solvedByTheme, {'fork': 1, 'discovered': 1, 'endgame': 1});
      expect(agg.attemptedByTheme, {'fork': 2, 'discovered': 1, 'endgame': 1});
    });

    test('recent fail rate respects window size (most recent first)', () {
      final rows = [
        // Most recent 3 attempts all failed.
        row('p1', 'failed', '2026-04-20T10:00:00Z'),
        row('p2', 'failed', '2026-04-19T10:00:00Z'),
        row('p1', 'failed', '2026-04-18T10:00:00Z'),
        // Older attempts were solved — should not count in a 2-wide window.
        row('p1', 'solved', '2026-04-10T10:00:00Z'),
        row('p2', 'solved', '2026-04-09T10:00:00Z'),
      ];
      final agg = AttemptAggregates.fromRows(
        rows,
        themesByPuzzle: themes,
        recentWindowPerTheme: 2,
      );
      // fork window in DESC order: [fail(p1), fail(p2)] — both fails, 100%.
      expect(agg.recentFailRateByTheme['fork'], 1.0);
    });

    test('last attempt per theme is the most recent across any of its puzzles',
        () {
      final rows = [
        row('p1', 'failed', '2026-04-20T10:00:00Z'),
        row('p2', 'solved', '2026-04-22T10:00:00Z'),
        row('p1', 'solved', '2026-04-15T10:00:00Z'),
      ];
      final agg = AttemptAggregates.fromRows(
        rows,
        themesByPuzzle: themes,
        recentWindowPerTheme: 10,
      );
      expect(
        agg.lastAttemptPerTheme['fork'],
        DateTime.parse('2026-04-22T10:00:00Z'),
      );
      // "discovered" only on p1 — newest p1 attempt is 2026-04-20.
      expect(
        agg.lastAttemptPerTheme['discovered'],
        DateTime.parse('2026-04-20T10:00:00Z'),
      );
    });

    test('puzzles with no theme mapping are ignored', () {
      final rows = [
        row('unknown', 'solved', '2026-04-20T10:00:00Z'),
      ];
      final agg = AttemptAggregates.fromRows(
        rows,
        themesByPuzzle: themes,
        recentWindowPerTheme: 10,
      );
      expect(agg.solvedByTheme, isEmpty);
      expect(agg.attemptedByTheme, isEmpty);
      expect(agg.lastAttemptPerTheme, isEmpty);
      expect(agg.recentFailRateByTheme, isEmpty);
    });

    test('empty input yields empty maps', () {
      final agg = AttemptAggregates.fromRows(
        const [],
        themesByPuzzle: themes,
        recentWindowPerTheme: 10,
      );
      expect(agg.solvedByTheme, isEmpty);
      expect(agg.attemptedByTheme, isEmpty);
      expect(agg.lastAttemptPerTheme, isEmpty);
      expect(agg.recentFailRateByTheme, isEmpty);
    });
  });
}
