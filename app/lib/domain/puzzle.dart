class Puzzle {
  final String id;
  final String fen;
  final String setupMove;
  final String sideToMove; // 'w' | 'b'
  final List<String> moves; // UCI, solver/opponent alternating, starting with solver
  final int rating;
  final int ratingDev;
  final int popularity;
  final int nbPlays;
  final double interest;
  final String originKind; // 'lichess' | 'study' | 'famous'
  final String? originLabel;
  final String? explanation;
  final List<String> themes;

  const Puzzle({
    required this.id,
    required this.fen,
    required this.setupMove,
    required this.sideToMove,
    required this.moves,
    required this.rating,
    required this.ratingDev,
    required this.popularity,
    required this.nbPlays,
    required this.interest,
    required this.originKind,
    required this.originLabel,
    required this.explanation,
    required this.themes,
  });
}

class ThemeInfo {
  final String id;
  final String displayName;
  final String description;
  final double importance;
  final int floorRating;
  final int ceilingRating;
  final List<String> prereqs;

  const ThemeInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.importance,
    required this.floorRating,
    required this.ceilingRating,
    required this.prereqs,
  });
}
