import 'package:dartchess/dartchess.dart';

import '../domain/puzzle.dart';

enum SolveState { idle, solving, succeeded, failed }

class MoveOutcome {
  final bool accepted;
  final bool puzzleComplete;
  final NormalMove? opponentReply;
  const MoveOutcome({
    required this.accepted,
    required this.puzzleComplete,
    this.opponentReply,
  });
}

/// State machine for a single puzzle.
///
/// On [tryMove], we advance the position by the player's move ONLY. If the
/// move is correct and the puzzle has another opponent reply, the reply is
/// returned in [MoveOutcome.opponentReply] — the caller is responsible for
/// calling [applyOpponentReply] after the player-move animation has settled.
/// This two-step flow lets the UI animate the two moves separately instead
/// of teleporting through them.
class PuzzleController {
  final Puzzle puzzle;
  Position _position;
  int _solverPly;
  SolveState _state = SolveState.solving;
  String? _firstWrongUci;
  NormalMove? _lastMove;
  bool _awaitingOpponentReply = false;

  PuzzleController(this.puzzle)
      : _position = _initialPosition(puzzle),
        _solverPly = 0;

  static Position _initialPosition(Puzzle puz) {
    final setup = Setup.parseFen(puz.fen);
    Position pos = Chess.fromSetup(setup);
    if (puz.setupMove.isNotEmpty) {
      pos = pos.play(NormalMove.fromUci(puz.setupMove));
    }
    return pos;
  }

  SolveState get state => _state;
  Position get position => _position;
  String? get firstWrongUci => _firstWrongUci;

  /// The move most recently applied to the board (for lastMove highlighting).
  NormalMove? get lastMove => _lastMove;

  /// Apply the player's move. Returns a [MoveOutcome]; if `opponentReply` is
  /// non-null, caller should [applyOpponentReply] after the player-move
  /// animation has settled.
  MoveOutcome tryMove(String uci) {
    if (_state != SolveState.solving) {
      return const MoveOutcome(accepted: false, puzzleComplete: false);
    }
    // Between tryMove returning a reply and the caller applying it,
    // [_solverPly] points at the OPPONENT's scripted ply. Accepting a move
    // here would grade the player against the opponent's move.
    if (_awaitingOpponentReply) {
      return const MoveOutcome(accepted: false, puzzleComplete: false);
    }
    final expected = puzzle.moves[_solverPly];
    if (!_matches(uci, expected)) {
      _firstWrongUci ??= uci;
      // Play the wrong move onto the board so the player SEES what they
      // did before the post-puzzle screen appears (their ask: complete
      // the move, pause, then show failed). Legal-move validation is
      // already done upstream by chessground, so .play() should succeed
      // for any piece-and-square combo reachable via drag.
      try {
        final mv = NormalMove.fromUci(uci);
        _position = _position.play(mv);
        _lastMove = mv;
      } catch (_) {
        // If the move isn't legal (shouldn't happen — chessground
        // gatekeeps), skip the visual apply and just mark failed.
      }
      _state = SolveState.failed;
      return const MoveOutcome(accepted: false, puzzleComplete: false);
    }
    final mv = NormalMove.fromUci(uci);
    _position = _position.play(mv);
    _lastMove = mv;
    _solverPly += 1;
    // Any opponent reply waiting?
    if (_solverPly < puzzle.moves.length) {
      final reply = NormalMove.fromUci(puzzle.moves[_solverPly]);
      _awaitingOpponentReply = true;
      return MoveOutcome(
        accepted: true,
        puzzleComplete: false,
        opponentReply: reply,
      );
    }
    _state = SolveState.succeeded;
    return const MoveOutcome(accepted: true, puzzleComplete: true);
  }

  /// Advance through the opponent's scripted reply. Should be called by the
  /// UI after the solver-move animation has settled (~250ms).
  bool applyOpponentReply() {
    if (!_awaitingOpponentReply) return false;
    _awaitingOpponentReply = false;
    if (_solverPly >= puzzle.moves.length) return false;
    final reply = NormalMove.fromUci(puzzle.moves[_solverPly]);
    _position = _position.play(reply);
    _lastMove = reply;
    _solverPly += 1;
    if (_solverPly >= puzzle.moves.length) {
      _state = SolveState.succeeded;
    }
    return true;
  }

  /// Whether [playerUci] solves the current ply.
  ///
  /// Exact string equality is not sufficient. Castling has two accepted UCI
  /// spellings (king-to-rook `e1h1` and king-two-squares `e1g1`), and at the
  /// final ply any legal move that delivers mate ends the puzzle just as the
  /// scripted one does — Lichess grades it correct, and grading it wrong
  /// costs the player rating for finding an equally good mate.
  bool _matches(String playerUci, String expectedUci) {
    if (playerUci == expectedUci) return true;

    final NormalMove player;
    try {
      player = NormalMove.fromUci(playerUci);
    } catch (_) {
      return false;
    }
    if (!_position.isLegal(player)) return false;

    try {
      final expected = NormalMove.fromUci(expectedUci);
      if (_position.normalizeMove(player) == _position.normalizeMove(expected)) {
        return true;
      }
    } catch (_) {
      // Fall through — a malformed scripted move cannot be matched by
      // normalization, but an alternate mate may still solve the puzzle.
    }

    if (_solverPly == puzzle.moves.length - 1) {
      return _position.play(player).isCheckmate;
    }
    return false;
  }
}
