import 'dart:async';
import 'dart:math' as math;

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessground/chessground.dart' as cg;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs.dart';
import '../../domain/rating_tier.dart';
import '../../theme/app_theme.dart';

import '../../data/providers.dart';
import '../../data/puzzle_controller.dart';
import '../../domain/puzzle.dart';
import '../../widgets/fast_fade_route.dart';
import '../post_puzzle/post_puzzle_screen.dart';

class SolveScreen extends ConsumerStatefulWidget {
  final String? themeFocus;
  final String? specificPuzzleId;
  const SolveScreen({super.key, this.themeFocus, this.specificPuzzleId});

  @override
  ConsumerState<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends ConsumerState<SolveScreen> {
  // How long chessground takes to animate a move. Must match the
  // animationDuration we pass in settings below.
  static const _animDuration = Duration(milliseconds: 220);

  /// specs/hints-and-analyze.md: a Give up button appears after this
  /// many seconds of inactivity on the same position. Tapping it marks
  /// the puzzle failed.
  static const _giveUpAfter = Duration(seconds: 30);

  Puzzle? _puzzle;
  PuzzleController? _ctrl;
  bool _busy = false;

  /// Bumped whenever the board is reset under a move that is still
  /// animating. `_applyMove` awaits between the player's move and the
  /// scripted reply; a restart inside that window swaps in a fresh
  /// controller, and the in-flight continuation would otherwise resume
  /// against it — replaying the solution's own first move onto the reset
  /// board and then grading the player's next correct move as wrong.
  int _generation = 0;

  /// Whether the continuation that started at [generation] still owns the
  /// solve. A restart resets [_busy] itself, so a superseded continuation
  /// must return without touching it.
  bool _stillCurrent(int generation) => mounted && generation == _generation;
  NormalMove? _pendingPromotion;

  /// Wall clock when the player was first given control of the puzzle.
  /// Used to record solve duration for per-puzzle stats. Excluded from
  /// average if > 3 min (phone-put-down outlier).
  DateTime? _solveStart;

  /// True once the give-up window has elapsed without a move. Reset on
  /// each accepted move.
  bool _canGiveUp = false;
  Timer? _giveUpTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _giveUpTimer?.cancel();
    super.dispose();
  }

  /// Start (or restart) the 30-second countdown that reveals the Give
  /// up button.
  void _armGiveUpTimer() {
    _giveUpTimer?.cancel();
    if (_canGiveUp) {
      // Collapse back to hidden when a move resets the timer.
      _canGiveUp = false;
    }
    _giveUpTimer = Timer(_giveUpAfter, () {
      if (!mounted) return;
      setState(() => _canGiveUp = true);
    });
  }

  Future<void> _giveUp() async {
    if (_busy || _ctrl == null) return;
    _busy = true;
    final generation = _generation;
    _giveUpTimer?.cancel();
    // No "first wrong move" is recorded — the player didn't try anything
    // incorrect, just ran out of ideas. firstWrongUci stays null.
    await _finish(solved: false);
    if (_stillCurrent(generation)) _busy = false;
  }

  /// Reset the board to the puzzle's starting position without navigating
  /// away. Does NOT re-fetch a different puzzle — this is "try this one
  /// again from the start." Doesn't clear the failure record either: a
  /// mistake that's already been logged counts.
  void _restart() {
    final puzzle = _puzzle;
    if (puzzle == null) return;
    setState(() {
      _generation++;
      _ctrl = PuzzleController(puzzle);
      _pendingPromotion = null;
      _busy = false;
      _solveStart = DateTime.now();
      _canGiveUp = false;
    });
    _armGiveUpTimer();
  }

  Future<void> _load() async {
    Puzzle? p;
    try {
      if (widget.specificPuzzleId != null) {
        final pzDb = await ref.read(puzzleDbProvider.future);
        p = await pzDb.byId(widget.specificPuzzleId!);
        // Extremely unlikely: the id points to nothing. Fall back to any.
        p ??= await pzDb.anyPuzzle();
      } else {
        final svc = await ref.read(selectionServiceProvider.future);
        p = await svc.pickNext(
            themeFocus: widget.themeFocus, now: DateTime.now());
        // The selection service is supposed to always return something;
        // still, belt-and-braces — pull any puzzle if null.
        if (p == null) {
          final pzDb = await ref.read(puzzleDbProvider.future);
          p = await pzDb.anyPuzzle();
        }
      }
    } catch (e, st) {
      debugPrint('[solve] _load ERROR: $e\n$st');
      // Try once more, fully ignoring selection logic.
      try {
        final pzDb = await ref.read(puzzleDbProvider.future);
        p = await pzDb.anyPuzzle();
      } catch (_) {/* give up */}
    }
    if (!mounted) return;
    if (p == null) {
      // DB is truly empty — pop back to the dashboard so the player isn't
      // stuck on a spinner. Should never happen in shipped builds.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _puzzle = p;
      _ctrl = PuzzleController(p!);
      _solveStart = DateTime.now();
      _canGiveUp = false;
    });
    _armGiveUpTimer();
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = _puzzle;
    final ctrl = _ctrl;
    if (puzzle == null || ctrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final playerSide = ctrl.position.turn;
    final boardSide = puzzle.sideToMove == 'w' ? Side.white : Side.black;
    final playerSideEnum = playerSide == Side.white
        ? cg.PlayerSide.white
        : cg.PlayerSide.black;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          tooltip: 'Dashboard',
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
        title: _MissionTitle(rating: puzzle.rating),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Restart puzzle',
            onPressed: _restart,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, outer) {
            // The board shares the column with a "side to move" caption
            // (~36px) and the give-up row (~48px). Reserving only 56 for
            // both overflowed in landscape and on tablets, pushing the
            // give-up button off-screen where it could not be tapped.
            const reserved = 100.0;
            final avail = outer.biggest;
            final boardSize = avail.shortestSide
                .clamp(200.0, math.max(200.0, avail.height - reserved))
                .clamp(200.0, 1200.0)
                .toDouble();
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    puzzle.sideToMove == 'w'
                        ? 'White to move'
                        : 'Black to move',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Center(
                  // chessground contributes no semantics of its own, so
                  // without this the board is a blank region to a screen
                  // reader. This is a floor, not the square-by-square grid
                  // specs/accessibility.md describes, but it at least
                  // announces the position and whose move it is.
                  child: Semantics(
                    label: _boardSemanticLabel(ctrl),
                    container: true,
                    child: cg.Chessboard(
                    size: boardSize,
                    orientation: boardSide,
                    fen: ctrl.position.fen,
                    lastMove: ctrl.lastMove,
                    settings: cg.ChessboardSettings(
                      // Every other animation in the app honours
                      // disableAnimations; the board — the one the spec
                      // names explicitly — did not.
                      animationDuration:
                          MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : _animDuration,
                      showLastMove: true,
                      // Support both drag-and-drop and tap-to-select-then-
                      // tap-destination, so the player can use whichever
                      // method feels natural on mobile.
                      pieceShiftMethod: cg.PieceShiftMethod.either,
                      dragFeedbackScale: 1.1,
                    ),
                    game: cg.GameData(
                      playerSide: _busy ? cg.PlayerSide.none : playerSideEnum,
                      sideToMove: playerSide,
                      validMoves: _validMovesOf(ctrl.position),
                      promotionMove: _pendingPromotion,
                      onMove: _onMove,
                      onPromotionSelection: _onPromotionSelection,
                    ),
                    ),
                  ),
                ),
                // Give-up surface: hidden until the player has been idle
                // for _giveUpAfter, then fades in. Tapping it marks the
                // puzzle failed without a recorded first-wrong-move.
                AnimatedOpacity(
                  opacity: _canGiveUp && !_busy ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_canGiveUp || _busy,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton.icon(
                        onPressed: _giveUp,
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: const Text('Give up'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// [Position.legalMoves] encodes castling in its Chess960 form — king onto
  /// its own rook — so building the destination map by hand omits the `e1g1`
  /// / `e1c1` squares a player actually drags to, leaving every castling
  /// puzzle unenterable. [makeLegalMoves] adds those alternate destinations.
  /// Screen-reader description of the board.
  ///
  /// Reads the FEN placement field into plain language. Not a substitute for
  /// per-square navigation, but it makes the position audible at all.
  String _boardSemanticLabel(PuzzleController ctrl) {
    const names = {
      'p': 'pawn', 'n': 'knight', 'b': 'bishop',
      'r': 'rook', 'q': 'queen', 'k': 'king',
    };
    final placement = ctrl.position.fen.split(' ').first;
    final ranks = placement.split('/');
    final parts = <String>[];
    for (var r = 0; r < ranks.length; r++) {
      var file = 0;
      for (final ch in ranks[r].split('')) {
        final empty = int.tryParse(ch);
        if (empty != null) {
          file += empty;
          continue;
        }
        final square =
            '${String.fromCharCode(97 + file)}${8 - r}';
        final colour = ch == ch.toUpperCase() ? 'White' : 'Black';
        parts.add('$colour ${names[ch.toLowerCase()] ?? ch} $square');
        file += 1;
      }
    }
    final turn = ctrl.position.turn == Side.white ? 'White' : 'Black';
    return '$turn to move. ${parts.join(', ')}.';
  }

  IMap<Square, ISet<Square>> _validMovesOf(Position pos) =>
      makeLegalMoves(pos);

  void _onMove(NormalMove move, {bool? isDrop}) {
    if (_ctrl == null) return;
    final pos = _ctrl!.position;
    final piece = pos.board.pieceAt(move.from);
    if (piece != null &&
        piece.role == Role.pawn &&
        ((piece.color == Side.white && move.to.rank == Rank.eighth) ||
            (piece.color == Side.black && move.to.rank == Rank.first)) &&
        move.promotion == null) {
      setState(() => _pendingPromotion = move);
      return;
    }
    _applyMove(move.uci);
  }

  void _onPromotionSelection(Role? role) {
    final pending = _pendingPromotion;
    if (pending == null) {
      setState(() => _pendingPromotion = null);
      return;
    }
    if (role == null) {
      setState(() => _pendingPromotion = null);
      return;
    }
    final promoted =
        NormalMove(from: pending.from, to: pending.to, promotion: role);
    setState(() => _pendingPromotion = null);
    _applyMove(promoted.uci);
  }

  Future<void> _applyMove(String uci) async {
    if (_busy || _ctrl == null) return;
    _busy = true;
    final generation = _generation;
    final outcome = _ctrl!.tryMove(uci);
    if (!_stillCurrent(generation)) {
      if (mounted) _busy = false;
      return;
    }
    setState(() {});

    if (_ctrl!.state == SolveState.failed) {
      // Wrong move: piece has already landed on its destination (see
      // PuzzleController.tryMove). Hold long enough for the animation
      // to finish plus a beat so the player registers what they did,
      // THEN transition to the post-puzzle screen.
      _giveUpTimer?.cancel();
      await _hapticTick(heavy: true);
      // Commit the miss BEFORE the animation beat, not after. Persisting it
      // behind the delay let a player dodge every failure — and the rating
      // loss — by tapping Restart or Home inside a 720 ms window.
      await _finish(
        solved: false,
        settle: _animDuration + const Duration(milliseconds: 500),
      );
      if (mounted) _busy = false;
      return;
    }
    // Player made a legitimate move; reset the give-up idle timer so the
    // button vanishes again until another idle stretch.
    _armGiveUpTimer();
    await _hapticTick(heavy: outcome.puzzleComplete);

    // Animate the solver move; then play the scripted opponent reply.
    if (outcome.opponentReply != null) {
      await Future.delayed(_animDuration);
      // Restart during this window has already swapped in a fresh
      // controller and cleared _busy. Resuming here would play the
      // solution's first move onto the reset board.
      if (!_stillCurrent(generation)) return;
      _ctrl!.applyOpponentReply();
      setState(() {});
      if (_ctrl!.state == SolveState.succeeded) {
        await _finish(
          solved: true,
          settle: _animDuration + const Duration(milliseconds: 100),
        );
        if (mounted) _busy = false;
        return;
      }
      // Not complete: hand control back to the player.
      _busy = false;
      return;
    }

    // No opponent reply: puzzle complete on the player's move.
    if (_ctrl!.state == SolveState.succeeded) {
      await _finish(
        solved: true,
        settle: _animDuration + const Duration(milliseconds: 100),
      );
    }
    if (mounted) _busy = false;
  }

  /// Persist the outcome, then navigate to the post-puzzle screen.
  ///
  /// [settle] is held AFTER the result is written and before navigating, so
  /// the player sees the final board state. The wait must never gate the
  /// write: an outcome that is only persisted once an animation finishes can
  /// be escaped by leaving the screen.
  Future<void> _finish({required bool solved, Duration? settle}) async {
    if (!mounted || _puzzle == null) return;
    _giveUpTimer?.cancel();
    final puzzle = _puzzle!;
    final firstWrong = _ctrl?.firstWrongUci;
    final playerDb = await ref.read(playerDbProvider.future);

    // Time each DB step so a slow resolution can be attributed. The
    // breakdown is printed under the FINISH tag once the puzzle resolves.
    final swTotal = Stopwatch()..start();
    final profile = <String, int>{};
    Future<T> step<T>(String label, Future<T> Function() fn) async {
      final sw = Stopwatch()..start();
      final v = await fn();
      profile[label] = sw.elapsedMilliseconds;
      return v;
    }

    final global = await step('globalRating', playerDb.globalRating);
    final before = global.rating;
    global.update(
      opponentRating: puzzle.rating.toDouble(),
      opponentRd: puzzle.ratingDev.toDouble(),
      score: solved ? 1.0 : 0.0,
    );
    final themeRatings = <String, Glicko2>{};
    for (int i = 0; i < puzzle.themes.length; i++) {
      final t = puzzle.themes[i];
      final g = await step('themeRead[$i]', () => playerDb.themeRating(t));
      g.update(
        opponentRating: puzzle.rating.toDouble(),
        opponentRd: puzzle.ratingDev.toDouble(),
        score: solved ? 1.0 : 0.0,
        weight: i == 0 ? 1.0 : 0.5,
      );
      themeRatings[t] = g;
    }
    final delta = global.rating - before;
    final durationMs = _solveStart == null
        ? null
        : DateTime.now().difference(_solveStart!).inMilliseconds;
    // Decide the review-queue outcome BEFORE writing, so the rating, the
    // attempt row and the schedule all land in one transaction. A rating
    // that moved without its attempt row is permanently inconsistent —
    // every dashboard statistic is derived from `attempts`.
    final fsrs = Fsrs();
    final existingCard =
        await step('reviewFor', () => playerDb.reviewFor(puzzle.id));
    FsrsCard? reviewCard;
    var reviewRating = 1;
    var clearReview = false;
    if (solved) {
      if (existingCard != null) {
        final rating = firstWrong == null ? Rating.good : Rating.hard;
        fsrs.review(existingCard, rating, DateTime.now());
        if (rating == Rating.good &&
            existingCard.stability > 21.0 &&
            existingCard.reps >= 3) {
          clearReview = true;
        } else {
          reviewCard = existingCard;
          reviewRating = ratingToInt(rating);
        }
      }
    } else {
      reviewCard = existingCard ?? FsrsCard();
      fsrs.review(reviewCard, Rating.again, DateTime.now());
      reviewRating = 1;
    }

    await step(
        'commitResolution',
        () => playerDb.commitResolution(
              global: global,
              themeRatings: themeRatings,
              puzzleId: puzzle.id,
              outcome: solved ? 'solved' : 'failed',
              firstWrongMoveUci: firstWrong,
              ratingDeltaGlobal: delta,
              solveDurationMs: durationMs,
              reviewCard: reviewCard,
              reviewRating: reviewRating,
              clearReview: clearReview,
            ));
    // If we're in calibration, advance the binary-search state.
    // (The Glicko delta we wrote above is a no-op during calibration
    // because advanceCalibration overwrites the rating when it finishes.)
    final calState = await step('calibrationState', playerDb.calibrationState);
    if (!calState.$1) {
      await step('advanceCalibration',
          () => playerDb.advanceCalibration(solved: solved));
    }
    final totalMs = swTotal.elapsedMilliseconds;
    final top = profile.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topStr = top.take(6).map((e) => '${e.key}=${e.value}ms').join(' ');
    // ignore: avoid_print
    print('[FINISH] total=${totalMs}ms $topStr');

    // The result is now durable; hold only for the visual beat.
    if (settle != null) await Future.delayed(settle);

    if (!mounted) return;
    // Invalidate derived providers so the dashboard shows fresh stats
    // the instant the player returns — accuracy, missed count, and
    // per-theme progress all depend on attempts we just wrote.
    ref.invalidate(journeyProvider);
    ref.invalidate(globalRatingProvider);
    Navigator.of(context).pushReplacement(
      FastFadeRoute(
        builder: (_) => PostPuzzleScreen(
          puzzle: puzzle,
          solved: solved,
          ratingDelta: delta,
        ),
      ),
    );
  }

  Future<void> _hapticTick({required bool heavy}) async {
    try {
      final prefs = await ref.read(prefsProvider.future);
      if (!prefs.getBool(Prefs.kHapticsOn, defaultValue: true)) return;
      if (heavy) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    } catch (_) {
      // Desktop builds may not implement haptics; silently skip.
    }
  }
}

/// AppBar title + a 1-10 difficulty badge derived from the puzzle's
/// Glicko rating. The badge color runs green → amber → red so the player
/// sees at a glance how hard the current mission is.
/// Compact AppBar title designed to fit on a 360dp phone with
/// leading + 2 action icons (≈ 200 px free). Shows only the color-
/// coded difficulty number and the rating — no wordmark, no segment
/// bar. The bar can be reintroduced below the AppBar as a separate
/// strip if we want it later.
class _MissionTitle extends StatelessWidget {
  final int rating;
  const _MissionTitle({required this.rating});

  @override
  Widget build(BuildContext context) {
    final d = difficulty1to10(rating);
    final color = difficultyColor(d);
    final disp = displayRating(rating.toDouble());
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Difficulty chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'D$d',
              style: TextStyle(
                fontFamily: 'monospace',
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$disp',
            style: const TextStyle(
              fontFamily: 'monospace',
              color: WR.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
