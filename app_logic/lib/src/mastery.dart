/// Compute per-theme mastery ∈ [0, 1] from the player's rating in the theme
/// and the theme's floor/ceiling ratings.
double mastery({
  required double playerRating,
  required int floorRating,
  required int ceilingRating,
}) {
  // Degenerate range (bad theme data): fall back to a step function rather
  // than a constant 0.0, which would make the theme look permanently weak
  // and dead-end every unlock chain that lists it as a prereq.
  if (ceilingRating <= floorRating) {
    return playerRating >= floorRating ? 1.0 : 0.0;
  }
  final t = (playerRating - floorRating) / (ceilingRating - floorRating);
  return t.clamp(0.0, 1.0);
}

bool isUnlocked({
  required List<String> prereqs,
  required double Function(String themeId) masteryOf,
  double threshold = 0.5,
}) {
  for (final p in prereqs) {
    if (masteryOf(p) < threshold) return false;
  }
  return true;
}
