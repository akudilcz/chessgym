import 'dart:async';
import 'dart:math' as math;

import 'package:chesspuzzle_logic/chesspuzzle_logic.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessground/chessground.dart' as cg;
import 'package:flutter/foundation.dart' show kDebugMode;
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

  /// Drives the chessground board. Since chessground 10 the board renders
  /// from this controller rather than from widget parameters, so every
  /// position change has to be pushed with [_syncBoard] — a plain setState
  /// no longer moves the pieces.
  cg.ChessboardController? _board;

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
    // The board attaches to the controller but never disposes it; that is
    // the owner's job.
    _board?.dispose();
    super.dispose();
  }

  /// Board state for the current controller, as chessground wants it.
  ///
  /// [_busy] is folded in here rather than into the widget: with the
  /// position living in the controller, `PlayerSide.none` is how the board
  /// is locked while a reply animates or the outcome is being written.
  cg.GameData _buildGame() {
    final ctrl = _ctrl!;
    final turn = ctrl.position.turn;
    return cg.GameData(
      fen: ctrl.position.fen,
      lastMove: ctrl.lastMove,
      playerSide: _busy
          ? cg.PlayerSide.none
          : (turn == Side.white ? cg.PlayerSide.white : cg.PlayerSide.black),
      sideToMove: turn,
      validMoves: _validMovesOf(ctrl.position),
    );
  }

  /// Push the current position to the board.
  ///
  /// [animate] is false when the board jumps rather than moves — a restart,
  /// or the first position of a freshly loaded puzzle.
  void _syncBoard({bool animate = true}) {
    if (_ctrl == null) return;
    final game = _buildGame();
    final board = _board;
    if (board == null) {
      _board = cg.ChessboardController(game: game);
    } else {
      board.updatePosition(game, animate: animate, resetPremove: !animate);
    }
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
      _busy = false;
      _solveStart = DateTime.now();
      _canGiveUp = false;
    });
    // A restart is a jump, not a move — no slide animation, and any pending
    // premove from the abandoned attempt is dropped.
    _syncBoard(animate: false);
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
        // Share the dashboard's journey snapshot rather than letting
        // pickNext recompute it: the snapshot is expensive and runs on the
        // UI isolate. journeyProvider is invalidated after every resolution,
        // so this is never stale.
        final snap = await ref.read(journeyProvider.future);
        p = await svc.pickNext(
            themeFocus: widget.themeFocus,
            now: DateTime.now(),
            snapshot: snap);
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
    // Construct the controller BEFORE setState: it parses the FEN and
    // setup move, so a single corrupt corpus row would otherwise throw
    // mid-setState and hard-crash the screen instead of degrading.
    PuzzleController? ctrl;
    if (p != null) {
      try {
        ctrl = PuzzleController(p);
      } catch (e, st) {
        debugPrint('[solve] corrupt puzzle ${p.id}: $e\n$st');
        p = null;
      }
    }
    if (p == null || ctrl == null) {
      // DB is truly empty (or the row was corrupt) — pop back to the
      // dashboard so the player isn't stuck on a spinner. Should never
      // happen in shipped builds.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _puzzle = p;
      _ctrl = ctrl;
      _solveStart = DateTime.now();
      _canGiveUp = false;
    });
    _syncBoard(animate: false);
    _armGiveUpTimer();
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = _puzzle;
    final ctrl = _ctrl;
    final board = _board;
    if (puzzle == null || ctrl == null || board == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final boardSide = puzzle.sideToMove == 'w' ? Side.white : Side.black;

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
                    controller: board,
                    onMove: _onMove,
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
                      // Puzzles are single-player and every reply is
                      // scripted, so there is nothing to premove against.
                      enablePremoves: false,
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

  cg.ValidMoves _validMovesOf(Position pos) => makeLegalMoves(pos);

  /// The board resolves promotions itself now: it shows the piece selector
  /// and only calls back once, with [move.promotion] already set.
  void _onMove(Move move, {bool? viaDragAndDrop}) {
    if (_ctrl == null) return;
    _applyMove(move.uci);
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
    _syncBoard();

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
      _syncBoard();
      if (_ctrl!.state == SolveState.succeeded) {
        await _finish(
          solved: true,
          settle: _animDuration + const Duration(milliseconds: 100),
        );
        if (mounted) _busy = false;
        return;
      }
      // Not complete: hand control back to the player. The board is locked
      // via PlayerSide.none while busy, so it needs re-syncing to unlock.
      _busy = false;
      _syncBoard(animate: false);
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
    final generation = _generation;
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
        final previousRating = existingCard.lastRating;
        fsrs.review(existingCard, rating, DateTime.now());
        if (graduatesReview(
          rating: rating,
          previousRating: previousRating,
          stability: existingCard.stability,
        )) {
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
    if (kDebugMode) {
      final totalMs = swTotal.elapsedMilliseconds;
      final top = profile.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topStr = top.take(6).map((e) => '${e.key}=${e.value}ms').join(' ');
      debugPrint('[FINISH] total=${totalMs}ms $topStr');
    }

    // The result is now durable; hold only for the visual beat.
    if (settle != null) await Future.delayed(settle);

    // Restart during the settle window swapped in a fresh board; navigating
    // now would yank it away. The outcome above is already persisted, so
    // bailing out loses nothing.
    if (!mounted || !_stillCurrent(generation)) return;
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
