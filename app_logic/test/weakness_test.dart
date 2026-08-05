import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('weaknessScore', () {
    test('is in [0,1]', () {
      final v = weaknessScore(mastery: 0.3, attempts: 10, solved: 4, rd: 80);
      expect(v, inInclusiveRange(0.0, 1.0));
    });

    test('fully-mastered, low-RD is near zero', () {
      final v = weaknessScore(
          mastery: 1.0, attempts: 200, solved: 200, rd: 30);
      expect(v, lessThan(0.1));
    });

    test('untouched theme (cold start) scores moderately high', () {
      final v = weaknessScore(
          mastery: 0.3, attempts: 0, solved: 0, rd: 350);
      expect(v, greaterThan(0.4));
    });

    test('failure rate pushes it up', () {
      final high = weaknessScore(
          mastery: 0.5, attempts: 10, solved: 1, rd: 80);
      final low = weaknessScore(
          mastery: 0.5, attempts: 10, solved: 9, rd: 80);
      expect(high, greaterThan(low));
    });

    test('high RD bumps weakness for exploration', () {
      final a = weaknessScore(mastery: 0.5, attempts: 3, solved: 2, rd: 50);
      final b = weaknessScore(mastery: 0.5, attempts: 3, solved: 2, rd: 300);
      expect(b, greaterThan(a));
    });
  });

  group('sampleWithFloor', () {
    test('respects probability floor — weak theme still sometimes picked', () {
      // Two themes: one extremely weak (weight near 1), one very strong (near 0).
      // With alpha=2.5 and floor=0.05, the strong theme should still get a
      // non-trivial share thanks to the floor.
      final rng = math.Random(0);
      var strong = 0;
      for (var i = 0; i < 5000; i++) {
        final idx = sampleWithFloor([0.95, 0.01], rng, floor: 0.05);
        if (idx == 1) strong++;
      }
      // floor=0.05 is per item, so the strong theme gets at least a 5%
      // share: ≥~250 picks expected out of 5000.
      expect(strong, greaterThan(150), reason: 'floor should protect strong');
      expect(strong, lessThan(1500),
          reason: 'weak theme should still dominate');
    });

    test('empty weights throw instead of silently returning', () {
      expect(() => sampleWithFloor([], math.Random(0)),
          throwsA(isA<ArgumentError>()));
    });

    test('floor larger than 1/n degrades toward uniform, stays valid', () {
      final rng = math.Random(4);
      final counts = [0, 0, 0];
      for (var i = 0; i < 3000; i++) {
        counts[sampleWithFloor([0.9, 0.1, 0.1], rng, floor: 0.5)]++;
      }
      // Effective floor caps at 1/3, so the distribution is uniform.
      for (final c in counts) {
        expect(c, inInclusiveRange(800, 1200));
      }
    });

    test('equal weights → ~uniform', () {
      final rng = math.Random(1);
      final counts = [0, 0, 0, 0];
      for (var i = 0; i < 4000; i++) {
        counts[sampleWithFloor([0.5, 0.5, 0.5, 0.5], rng)]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(800, 1200));
      }
    });

    test('single theme returns index 0', () {
      final rng = math.Random(2);
      for (var i = 0; i < 10; i++) {
        expect(sampleWithFloor([0.5], rng), 0);
      }
    });

    test('zero weights fall back to uniform', () {
      final rng = math.Random(3);
      final counts = [0, 0, 0];
      for (var i = 0; i < 3000; i++) {
        counts[sampleWithFloor([0.0, 0.0, 0.0], rng)]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(800, 1200));
      }
    });
  });
}
