import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('Selection', () {
    final now = DateTime.utc(2026, 1, 1);

    PuzzleCandidate p(String id, int rating, double interest,
            {DateTime? lastSeen}) =>
        PuzzleCandidate(
          id: id,
          rating: rating,
          interest: interest,
          themes: const ['fork'],
          lastSeen: lastSeen,
        );

    test('returns null on empty input', () {
      final pick = Selection().pickNext(
        candidates: [],
        playerRating: 1200,
        now: now,
      );
      expect(pick, isNull);
    });

    test('stays within rating band when populated', () {
      final cands = [
        for (var i = 0; i < 50; i++) p('in$i', 1150 + i * 2, 0.5),
        p('too_low', 500, 0.9),
        p('too_high', 2400, 0.9),
      ];
      final sel = Selection(rng: math.Random(0));
      for (var i = 0; i < 100; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        expect(pick.rating, inInclusiveRange(1150, 1350));
      }
    });

    test('prefers higher-interest puzzles', () {
      final cands = [
        p('low', 1200, 0.1),
        p('high', 1200, 0.9),
      ];
      final sel = Selection(rng: math.Random(1));
      int high = 0, low = 0;
      for (var i = 0; i < 500; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        if (pick.id == 'high') high += 1;
        if (pick.id == 'low') low += 1;
      }
      expect(high, greaterThan(low * 3));
    });

    test('downweights recently-seen puzzles', () {
      final recent = now.subtract(const Duration(hours: 1));
      final cands = [
        p('seen', 1200, 0.9, lastSeen: recent),
        p('fresh', 1200, 0.9),
      ];
      final sel = Selection(rng: math.Random(2));
      int fresh = 0;
      for (var i = 0; i < 500; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        if (pick.id == 'fresh') fresh += 1;
      }
      expect(fresh, greaterThan(400));
    });

    test('widening is bounded by maxBandWiden, not by the player rating', () {
      // Fewer than minCandidates sit in the initial band, so the band
      // widens — but it must stop at playerRating + maxBandWiden (1700),
      // never reach a 2500-rated puzzle. Treating maxBandWiden as an
      // absolute rating rather than a width widens to ~playerRating*2 and
      // serves puzzles far beyond the player's reach.
      final cands = [
        for (var i = 0; i < 5; i++) p('near$i', 1300, 0.5),
        p('unreachable', 2500, 0.9),
      ];
      final sel = Selection(rng: math.Random(7));
      for (var i = 0; i < 200; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        expect(pick.rating, lessThanOrEqualTo(1700),
            reason: 'band widened past playerRating + maxBandWiden');
      }
    });

    test('widens band when nothing in range', () {
      final cands = [p('far', 2000, 0.5)];
      final sel = Selection(
        params: const SelectionParams(minCandidates: 1),
        rng: math.Random(3),
      );
      final pick = sel.pickNext(
          candidates: cands, playerRating: 800, now: now);
      expect(pick, isNotNull);
      expect(pick!.id, 'far');
    });

    test('never-seen puzzles are preferred over recently-seen ones', () {
      // Recent = within recencyExcludeHours. If a never-seen candidate
      // exists in the band, it should always beat a recently-seen one
      // regardless of interest weighting.
      final recent = now.subtract(const Duration(hours: 1));
      final cands = [
        PuzzleCandidate(
          id: 'seen_recent',
          rating: 1200,
          interest: 0.99,
          themes: const ['fork'],
          lastSeen: recent,
        ),
        PuzzleCandidate(
          id: 'never_seen',
          rating: 1200,
          interest: 0.01,
          themes: const ['fork'],
          lastSeen: null,
        ),
      ];
      final sel = Selection(rng: math.Random(4));
      int neverSeen = 0;
      for (var i = 0; i < 100; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        if (pick.id == 'never_seen') neverSeen += 1;
      }
      expect(neverSeen, 100,
          reason: 'never-seen tier must beat recently-seen regardless of '
              'interest');
    });

    test('already-solved puzzles are last-resort only', () {
      // When an unsolved, never-seen alternative exists, solved
      // candidates should never be chosen.
      final cands = [
        PuzzleCandidate(
          id: 'solved',
          rating: 1200,
          interest: 0.99,
          themes: const ['fork'],
          alreadySolved: true,
        ),
        PuzzleCandidate(
          id: 'unsolved',
          rating: 1200,
          interest: 0.01,
          themes: const ['fork'],
          alreadySolved: false,
        ),
      ];
      final sel = Selection(rng: math.Random(5));
      for (var i = 0; i < 100; i++) {
        final pick = sel.pickNext(
            candidates: cands, playerRating: 1200, now: now)!;
        expect(pick.id, 'unsolved');
      }
    });
  });

  group('Mastery', () {
    test('clamps and interpolates', () {
      expect(
        mastery(playerRating: 800, floorRating: 800, ceilingRating: 2000),
        closeTo(0.0, 1e-9),
      );
      expect(
        mastery(playerRating: 1400, floorRating: 800, ceilingRating: 2000),
        closeTo(0.5, 1e-9),
      );
      expect(
        mastery(playerRating: 2500, floorRating: 800, ceilingRating: 2000),
        closeTo(1.0, 1e-9),
      );
    });

    test('unlock requires all prereqs', () {
      final masteries = {'a': 0.6, 'b': 0.3};
      expect(
        isUnlocked(
          prereqs: ['a'],
          masteryOf: (id) => masteries[id] ?? 0.0,
        ),
        isTrue,
      );
      expect(
        isUnlocked(
          prereqs: ['a', 'b'],
          masteryOf: (id) => masteries[id] ?? 0.0,
        ),
        isFalse,
      );
    });
  });
}
