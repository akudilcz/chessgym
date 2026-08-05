import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('Fsrs', () {
    final t0 = DateTime.utc(2026, 1, 1);

    test('new card initialized on Again', () {
      final c = FsrsCard();
      Fsrs().review(c, Rating.again, t0);
      expect(c.stability, greaterThan(0));
      expect(c.difficulty, inInclusiveRange(1.0, 10.0));
      expect(c.reps, 1);
      expect(c.lapses, 1);
      expect(c.due, isNotNull);
    });

    test('Good after a lapse schedules further out than Again', () {
      final fsrs = Fsrs();
      final again = FsrsCard();
      fsrs.review(again, Rating.again, t0);
      final againDue = again.due!;

      final good = FsrsCard();
      fsrs.review(good, Rating.again, t0);
      fsrs.review(good, Rating.good, t0.add(Duration(minutes: 5)));
      final goodDue = good.due!;

      expect(goodDue.isAfter(againDue), isTrue);
    });

    test('repeated Good increases stability monotonically', () {
      final fsrs = Fsrs();
      final c = FsrsCard();
      fsrs.review(c, Rating.again, t0);
      var prev = c.stability;
      var now = t0;
      for (var i = 0; i < 5; i++) {
        now = c.due!.add(Duration(minutes: 5));
        fsrs.review(c, Rating.good, now);
        expect(c.stability, greaterThan(prev));
        prev = c.stability;
      }
    });

    test('Again resets stability downward', () {
      final fsrs = Fsrs();
      final c = FsrsCard();
      fsrs.review(c, Rating.again, t0);
      fsrs.review(c, Rating.good, t0.add(Duration(days: 1)));
      fsrs.review(c, Rating.good, c.due!.add(Duration(days: 1)));
      final stabilityBefore = c.stability;
      fsrs.review(c, Rating.again, c.due!.add(Duration(days: 1)));
      expect(c.stability, lessThan(stabilityBefore));
    });

    test('default weights are the FSRS-4 set the formulas expect', () {
      // The FSRS-5 parameter set is numerically plausible but wrong here:
      // FSRS-5 redefines w[5] as an exponent where these formulas use it as
      // a linear slope. The tell is initial difficulty — under FSRS-4,
      // D0(Good) is exactly w[4].
      expect(defaultWeights, hasLength(17));
      expect(defaultWeights[4], closeTo(4.93, 1e-9),
          reason: 'w[4] is D0(Good); 7.2102 is the FSRS-5 value');
      expect(defaultWeights[5], lessThan(1.0),
          reason: 'w[5] is a linear slope in FSRS-4, not an exponent');

      final good = FsrsCard();
      Fsrs().review(good, Rating.good, t0);
      expect(good.difficulty, closeTo(defaultWeights[4], 1e-9));
      // Every grade must land inside the valid difficulty band.
      for (final r in Rating.values) {
        final c = FsrsCard();
        Fsrs().review(c, r, t0);
        expect(c.difficulty, inInclusiveRange(1.0, 10.0));
        expect(c.stability, greaterThan(0.0));
      }
    });

    test('forgetting never lengthens the interval', () {
      // Short-stability cards are exactly where the raw forget formula
      // overshoots. A lapse that pushed the card further away would be the
      // opposite of what a review queue is for.
      for (final s in [0.2, 0.4072, 1.0, 3.0, 10.0]) {
        for (final d in [1.0, 5.0, 8.27, 10.0]) {
          final c = FsrsCard(
            stability: s,
            difficulty: d,
            reps: 3,
            lastReview: t0,
          );
          Fsrs().review(c, Rating.again, t0.add(const Duration(days: 19)));
          expect(c.stability, lessThanOrEqualTo(s + 1e-9),
              reason: 'lapse raised stability from $s (difficulty $d)');
        }
      }
    });

    test('a card rehydrated with zero stability does not go NaN', () {
      // reps > 0 with stability 0 is reachable from a stored row; pow(0, -w)
      // is infinite and 0 * infinity is NaN, which clamps to the MAXIMUM
      // interval and schedules the card ~100 years out.
      final c = FsrsCard(stability: 0.0, difficulty: 5.0, reps: 2);
      final interval = Fsrs().review(c, Rating.good, t0);
      expect(c.stability.isNaN, isFalse);
      expect(c.stability.isFinite, isTrue);
      expect(interval, lessThan(3650.0));
      expect(c.due!.year, lessThan(t0.year + 10));
    });

    test('a rehydrated card is not re-initialized', () {
      // Persistence does not store reps, so a card loaded from disk has
      // reps == 0 but a non-null lastReview. Treating it as new would
      // discard its accumulated stability and reset the schedule — the
      // interval must keep growing across app sessions instead.
      final c = FsrsCard(
        stability: 15.0,
        difficulty: 6.0,
        lastReview: t0,
        reps: 0,
      );
      expect(c.isNew, isFalse);
      Fsrs().review(c, Rating.good, t0.add(const Duration(days: 15)));
      expect(c.stability, greaterThan(15.0),
          reason: 'a recall must build on the stored stability, '
              'not restart from the initial-stability table');
    });

    test('Hard penalty and Easy bonus order the stability gains', () {
      FsrsCard cardWith(Rating r) {
        final c = FsrsCard(
          stability: 10.0,
          difficulty: 5.0,
          lastReview: t0,
          reps: 3,
        );
        Fsrs().review(c, r, t0.add(const Duration(days: 10)));
        return c;
      }

      final hard = cardWith(Rating.hard);
      final good = cardWith(Rating.good);
      final easy = cardWith(Rating.easy);
      expect(hard.stability, lessThan(good.stability),
          reason: 'w[15] hard penalty must dampen the gain');
      expect(easy.stability, greaterThan(good.stability),
          reason: 'w[16] easy bonus must amplify the gain');
    });

    test('Again increases difficulty, Easy decreases it', () {
      FsrsCard cardWith(Rating r) {
        final c = FsrsCard(
          stability: 10.0,
          difficulty: 5.0,
          lastReview: t0,
          reps: 3,
        );
        Fsrs().review(c, r, t0.add(const Duration(days: 10)));
        return c;
      }

      expect(cardWith(Rating.again).difficulty, greaterThan(5.0));
      expect(cardWith(Rating.easy).difficulty, lessThan(5.0));
    });

    test('a review dated before the last one cannot go negative', () {
      // Clock changes and backfilled history produce negative elapsed time.
      final c = FsrsCard(
        stability: 10.0,
        difficulty: 5.0,
        reps: 3,
        lastReview: t0,
      );
      Fsrs().review(c, Rating.good, t0.subtract(const Duration(days: 7)));
      expect(c.stability, greaterThan(0.0));
      expect(c.stability.isFinite, isTrue);
    });
  });
}
