import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('thompsonPick', () {
    test('single theme always picked', () {
      final rng = math.Random(0);
      for (var i = 0; i < 10; i++) {
        expect(
          thompsonPick(
            weakness: [0.5], uncertainty: [0.1], rng: rng),
          0,
        );
      }
    });

    test('dominant theme wins most of the time', () {
      final rng = math.Random(1);
      var wins = 0;
      for (var i = 0; i < 1000; i++) {
        final idx = thompsonPick(
          weakness: [0.2, 0.9], uncertainty: [0.1, 0.1], rng: rng);
        if (idx == 1) wins++;
      }
      expect(wins, greaterThan(900),
          reason: 'weakness 0.9 should crush 0.2 with low noise');
    });

    test('high uncertainty sometimes wins over weaker mean', () {
      // Theme A: mean 0.5, low SD. Theme B: mean 0.3, high SD.
      // B should still win roughly 10-30% of the time thanks to variance.
      final rng = math.Random(2);
      var bWins = 0;
      for (var i = 0; i < 5000; i++) {
        final idx = thompsonPick(
            weakness: [0.5, 0.3],
            uncertainty: [0.03, 0.30],
            rng: rng);
        if (idx == 1) bWins++;
      }
      expect(bWins, inInclusiveRange(400, 2500),
          reason: 'B should win noticeably but not dominate');
    });

    test('over many turns, distribution matches relative weakness', () {
      final rng = math.Random(3);
      final counts = [0, 0, 0, 0];
      for (var i = 0; i < 4000; i++) {
        final idx = thompsonPick(
            weakness: [0.4, 0.5, 0.6, 0.7],
            uncertainty: [0.1, 0.1, 0.1, 0.1],
            rng: rng);
        counts[idx]++;
      }
      // Strictly increasing counts.
      expect(counts[0], lessThan(counts[1]));
      expect(counts[1], lessThan(counts[2]));
      expect(counts[2], lessThan(counts[3]));
    });
  });
}
