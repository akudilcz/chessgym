import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('ReviewQueue', () {
    final now = DateTime.utc(2026, 1, 1);

    test('first failure schedules a review', () {
      final q = ReviewQueue(fsrs: Fsrs());
      q.onFirstFailure('p1', now);
      expect(q.cards.containsKey('p1'), isTrue);
      expect(q.cards['p1']!.due, isNotNull);
    });

    test('due returns only cards past their due date', () {
      final q = ReviewQueue(fsrs: Fsrs());
      q.onFirstFailure('p1', now);
      // Brand-new lapse is due ~1 day out; not due now.
      expect(q.dueIds(now), isEmpty);
      expect(q.dueIds(now.add(const Duration(days: 30))), contains('p1'));
    });

    test('session cap limits served ids', () {
      final q = ReviewQueue(fsrs: Fsrs(), sessionCap: 2);
      for (final id in ['a', 'b', 'c', 'd']) {
        q.onFirstFailure(id, now);
      }
      final future = now.add(const Duration(days: 60));
      expect(q.dueIds(future).length, 2, reason: 'cap limits preview to 2');
      q.onReview(puzzleId: 'a', rating: Rating.good, now: future);
      q.onReview(puzzleId: 'b', rating: Rating.good, now: future);
      // Cap reached.
      expect(q.dueIds(future), isEmpty);
    });

    test('graduates after two consecutive Goods with stability past 21 days',
        () {
      final q = ReviewQueue(fsrs: Fsrs());
      // Seed a mature card: one prior Good on the record, stability > 21.
      q.cards['p1'] = FsrsCard(
        stability: 40.0,
        difficulty: 4.0,
        lastReview: now,
        lastRating: Rating.good,
        reps: 4,
      );
      q.onReview(
          puzzleId: 'p1',
          rating: Rating.good,
          now: now.add(const Duration(days: 40)));
      expect(q.cards.containsKey('p1'), isFalse,
          reason: 'second consecutive Good on a stable card graduates it');
    });

    test('a single Good does not graduate — the streak must be consecutive',
        () {
      final q = ReviewQueue(fsrs: Fsrs());
      // Same stability, but the previous outcome was a lapse.
      q.cards['p1'] = FsrsCard(
        stability: 40.0,
        difficulty: 4.0,
        lastReview: now,
        lastRating: Rating.again,
        reps: 4,
      );
      q.onReview(
          puzzleId: 'p1',
          rating: Rating.good,
          now: now.add(const Duration(days: 40)));
      expect(q.cards.containsKey('p1'), isTrue,
          reason: 'one Good after a lapse is not two consecutive Goods');
    });

    test('Hard breaks the Good streak', () {
      final q = ReviewQueue(fsrs: Fsrs());
      q.cards['p1'] = FsrsCard(
        stability: 40.0,
        difficulty: 4.0,
        lastReview: now,
        lastRating: Rating.good,
        reps: 4,
      );
      q.onReview(
          puzzleId: 'p1',
          rating: Rating.hard,
          now: now.add(const Duration(days: 40)));
      expect(q.cards.containsKey('p1'), isTrue);
      // The next Good is the first of a new streak, not the second.
      q.onReview(
          puzzleId: 'p1',
          rating: Rating.good,
          now: now.add(const Duration(days: 80)));
      expect(q.cards.containsKey('p1'), isTrue);
    });

    test('low-stability cards never graduate regardless of streak', () {
      final q = ReviewQueue(fsrs: Fsrs());
      q.onFirstFailure('p1', now);
      var t = now;
      // Several consecutive Goods, but starting from lapse-level stability
      // the card stays well under the 21-day bar for the first reviews.
      for (var i = 0; i < 2; i++) {
        t = q.cards['p1']!.due!.add(const Duration(minutes: 5));
        q.onReview(puzzleId: 'p1', rating: Rating.good, now: t);
      }
      expect(q.cards.containsKey('p1'), isTrue,
          reason: 'stability ${q.cards['p1']?.stability} is below 21');
    });

    test('a repeat failure keeps the existing card history', () {
      final q = ReviewQueue(fsrs: Fsrs());
      q.onFirstFailure('p1', now);
      final t1 = now.add(const Duration(days: 2));
      q.onReview(puzzleId: 'p1', rating: Rating.good, now: t1);
      final repsBefore = q.cards['p1']!.reps;
      q.onFirstFailure('p1', t1.add(const Duration(days: 1)));
      expect(q.cards['p1']!.reps, repsBefore + 1,
          reason: 'the card must be rated Again in place, not replaced');
    });

    test('reset session clears counter', () {
      final q = ReviewQueue(fsrs: Fsrs(), sessionCap: 1);
      q.onFirstFailure('p1', now);
      q.onReview(
          puzzleId: 'p1', rating: Rating.again, now: now.add(const Duration(days: 1)));
      expect(q.servedThisSession, 1);
      q.resetSession();
      expect(q.servedThisSession, 0);
    });
  });
}
