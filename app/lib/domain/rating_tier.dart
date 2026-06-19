import 'package:flutter/material.dart';

/// Player tier derived from global rating. Purely visual — drives the tier
/// chip color and label. Cutoffs chosen to roughly match Lichess puzzle
/// rating distribution.
enum RatingTier {
  beginner,
  novice,
  intermediate,
  advanced,
  expert,
  master,
  grandmaster,
}

extension RatingTierLabel on RatingTier {
  String get label => switch (this) {
        RatingTier.beginner => 'Beginner',
        RatingTier.novice => 'Novice',
        RatingTier.intermediate => 'Intermediate',
        RatingTier.advanced => 'Advanced',
        RatingTier.expert => 'Expert',
        RatingTier.master => 'Master',
        RatingTier.grandmaster => 'Grandmaster',
      };

  IconData get icon => switch (this) {
        RatingTier.beginner => Icons.circle_outlined,
        RatingTier.novice => Icons.eco_outlined,
        RatingTier.intermediate => Icons.local_fire_department_outlined,
        RatingTier.advanced => Icons.flash_on_outlined,
        RatingTier.expert => Icons.star_outline,
        RatingTier.master => Icons.workspace_premium_outlined,
        RatingTier.grandmaster => Icons.emoji_events_outlined,
      };

  Color get color => switch (this) {
        RatingTier.beginner => const Color(0xFF9AA0A6),      // neutral grey
        RatingTier.novice => const Color(0xFF26A69A),        // teal400
        RatingTier.intermediate => const Color(0xFF42A5F5),  // blue400
        RatingTier.advanced => const Color(0xFFAB47BC),      // purple400
        RatingTier.expert => const Color(0xFFFFB300),        // amber600
        RatingTier.master => const Color(0xFFEF6C00),        // orange800
        RatingTier.grandmaster => const Color(0xFFD32F2F),   // red700
      };

  /// Rating at which this tier begins, on the DISPLAYED (international)
  /// scale. Aligned with rough FIDE/USCF bands so "Intermediate" means
  /// what club players expect it to mean.
  int get floor => switch (this) {
        RatingTier.beginner => 0,
        RatingTier.novice => 800,
        RatingTier.intermediate => 1100,
        RatingTier.advanced => 1400,
        RatingTier.expert => 1700,
        RatingTier.master => 2000,
        RatingTier.grandmaster => 2300,
      };
}

/// Classify by DISPLAYED rating (international scale). Callers should pass
/// displayRating(internal), not internal.
RatingTier tierFor(double displayedRating) {
  if (displayedRating >= 2300) return RatingTier.grandmaster;
  if (displayedRating >= 2000) return RatingTier.master;
  if (displayedRating >= 1700) return RatingTier.expert;
  if (displayedRating >= 1400) return RatingTier.advanced;
  if (displayedRating >= 1100) return RatingTier.intermediate;
  if (displayedRating >= 800) return RatingTier.novice;
  return RatingTier.beginner;
}

/// Points from current rating to the next tier floor; [1..tierGap].
int pointsToNextTier(double rating) {
  final tiers = RatingTier.values;
  final cur = tierFor(rating);
  final i = cur.index;
  if (i >= tiers.length - 1) return 0;
  return (tiers[i + 1].floor - rating).ceil();
}

/// 0..1 progress within the current tier toward the next one.
double tierProgress(double rating) {
  final tiers = RatingTier.values;
  final cur = tierFor(rating);
  final i = cur.index;
  if (i >= tiers.length - 1) return 1.0;
  final span = tiers[i + 1].floor - cur.floor;
  if (span <= 0) return 1.0;
  return ((rating - cur.floor) / span).clamp(0.0, 1.0);
}

/// Convert an internal Lichess-scale rating to a displayed "international"
/// rating. Lichess puzzle ratings are inflated ~300 points above FIDE/OTB
/// human ratings. We store on the Lichess scale (because that's what the
/// puzzles themselves are rated at and the Glicko math needs that), but
/// display on an international-aligned scale so "1200" means "mid-club
/// player" the way it does for FIDE.
int displayRating(double internalRating) {
  return (internalRating - 300).round();
}

int masteryStars(double mastery) {
  if (mastery >= 0.90) return 3;
  if (mastery >= 0.55) return 2;
  if (mastery >= 0.25) return 1;
  return 0;
}

/// Map a raw Glicko puzzle rating to a 1-10 difficulty scale. Cutoffs
/// chosen so "5" sits at intermediate club level (≈1500) and "10" is
/// genuinely hard for a strong club player.
int difficulty1to10(int rating) {
  if (rating < 800) return 1;
  if (rating < 1000) return 2;
  if (rating < 1200) return 3;
  if (rating < 1400) return 4;
  if (rating < 1600) return 5;
  if (rating < 1800) return 6;
  if (rating < 2000) return 7;
  if (rating < 2200) return 8;
  if (rating < 2400) return 9;
  return 10;
}

Color difficultyColor(int d) {
  // Cold (easy, green) → hot (hard, red) — matches the weakness palette.
  if (d <= 2) return const Color(0xFF39FF8C);
  if (d <= 4) return const Color(0xFF4DD0E1);
  if (d <= 6) return const Color(0xFFFFC400);
  if (d <= 8) return const Color(0xFFFF8F00);
  return const Color(0xFFFF5252);
}
