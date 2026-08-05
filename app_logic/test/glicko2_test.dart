import 'package:test/test.dart';
import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';

void main() {
  group('Glicko2', () {
    test('starts at defaults', () {
      final g = Glicko2();
      expect(g.rating, closeTo(1200.0, 1e-6));
      expect(g.rd, closeTo(350.0, 1e-6));
      expect(g.volatility, closeTo(0.06, 1e-6));
    });

    test('solve against a higher-rated puzzle raises rating', () {
      final g = Glicko2(rating: 1200, rd: 80, volatility: 0.06);
      g.update(opponentRating: 1400, opponentRd: 50, score: 1.0);
      expect(g.rating, greaterThan(1200));
    });

    test('fail against a lower-rated puzzle lowers rating', () {
      final g = Glicko2(rating: 1400, rd: 80, volatility: 0.06);
      g.update(opponentRating: 1200, opponentRd: 50, score: 0.0);
      expect(g.rating, lessThan(1400));
    });

    test('rd decreases with updates', () {
      final g = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      final before = g.rd;
      g.update(opponentRating: 1500, opponentRd: 100, score: 0.5);
      expect(g.rd, lessThan(before));
    });

    test('decay inflates rd when no games played', () {
      final g = Glicko2(rating: 1500, rd: 50, volatility: 0.06);
      final before = g.rd;
      g.decay();
      expect(g.rd, greaterThan(before));
    });

    test('rd never exceeds the unrated default, however long the layoff', () {
      final g = Glicko2(rating: 1500, rd: 340, volatility: 0.06);
      for (var i = 0; i < 500; i++) {
        g.decay();
      }
      expect(g.rd, lessThanOrEqualTo(350.0));
      expect(g.rd.isFinite, isTrue);
    });

    test('zero weight is a no-op — no rating, rd or volatility movement', () {
      final g = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      g.update(
          opponentRating: 1700, opponentRd: 50, score: 1.0, weight: 0.0);
      expect(g.rating, closeTo(1500.0, 1e-9));
      expect(g.rd, closeTo(200.0, 1e-9));
      expect(g.volatility, closeTo(0.06, 1e-9));
    });

    test('weight scales information: lighter attempts shrink rd less', () {
      final full = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      final half = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      full.update(opponentRating: 1500, opponentRd: 50, score: 1.0);
      half.update(
          opponentRating: 1500, opponentRd: 50, score: 1.0, weight: 0.5);
      // Both learn something, so both tighten...
      expect(full.rd, lessThan(200.0));
      expect(half.rd, lessThan(200.0));
      // ...but the half-weight attempt carries half the information, so it
      // must leave MORE uncertainty behind. A weight that only scaled the
      // rating step would leave these two equal.
      expect(half.rd, greaterThan(full.rd));
    });

    test('weight half-scales the rating update', () {
      final a = Glicko2(rating: 1500, rd: 80, volatility: 0.06);
      final b = Glicko2(rating: 1500, rd: 80, volatility: 0.06);
      a.update(opponentRating: 1700, opponentRd: 50, score: 1.0);
      b.update(opponentRating: 1700, opponentRd: 50, score: 1.0, weight: 0.5);
      final aDelta = a.rating - 1500.0;
      final bDelta = b.rating - 1500.0;
      expect(bDelta, lessThan(aDelta));
      expect(bDelta, greaterThan(0));
    });

    test('an extreme rating gap stays finite and still moves the rating', () {
      // At a gap of ~6400+ the win expectation rounds to exactly 1.0 in
      // doubles; unclamped, that makes v infinite and the update a no-op.
      final g = Glicko2(rating: 9000, rd: 80, volatility: 0.06);
      g.update(opponentRating: 600, opponentRd: 50, score: 0.0);
      expect(g.rating.isFinite, isTrue);
      expect(g.rd.isFinite, isTrue);
      expect(g.volatility.isFinite, isTrue);
      expect(g.rating, lessThan(9000.0),
          reason: 'losing to a far weaker opponent must cost rating');
    });

    test('weight above one is clamped — no fabricated information', () {
      final full = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      final over = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      full.update(opponentRating: 1500, opponentRd: 50, score: 1.0);
      over.update(
          opponentRating: 1500, opponentRd: 50, score: 1.0, weight: 5.0);
      expect(over.rating, closeTo(full.rating, 1e-9));
      expect(over.rd, closeTo(full.rd, 1e-9));
    });

    test('Glickman (2013) example: rating moves in expected direction', () {
      // Glickman worked example: player 1500/200, opponents with mixed results.
      final g = Glicko2(rating: 1500, rd: 200, volatility: 0.06);
      g.update(opponentRating: 1400, opponentRd: 30, score: 1.0);
      g.update(opponentRating: 1550, opponentRd: 100, score: 0.0);
      g.update(opponentRating: 1700, opponentRd: 300, score: 0.0);
      // Expected per Glickman: ~1464, RD ~152.
      expect(g.rating, closeTo(1464.0, 30.0));
      expect(g.rd, closeTo(152.0, 30.0));
    });
  });
}
