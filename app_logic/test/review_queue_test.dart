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
