import 'package:dartchess/dartchess.dart';
import 'package:chessground/chessground.dart' as cg;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/puzzle.dart';

class AnalyzeScreen extends ConsumerStatefulWidget {
  final Puzzle puzzle;
  const AnalyzeScreen({super.key, required this.puzzle});

  @override
  ConsumerState<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends ConsumerState<AnalyzeScreen> {
  late List<Position> _line;
  int _ply = 0;
  bool _flipped = false;
  final FocusNode _keyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _line = _buildLine();
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (_ply + delta).clamp(0, _line.length - 1);
    if (next != _ply) setState(() => _ply = next);
  }

  /// specs/accessibility.md: "arrow keys step through moves in analyze".
  /// Additional keys: Home/End jump to start/end; R resets (matches AppBar
  /// restart); F flips the board (matches AppBar flip).
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.space) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.home) {
      setState(() => _ply = 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.end) {
      setState(() => _ply = _line.length - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      setState(() => _flipped = !_flipped);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      setState(() => _ply = 0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Position> _buildLine() {
    final setup = Setup.parseFen(widget.puzzle.fen);
    Position pos = Chess.fromSetup(setup);
    if (widget.puzzle.setupMove.isNotEmpty) {
      pos = pos.play(NormalMove.fromUci(widget.puzzle.setupMove));
    }
    final out = <Position>[pos];
    for (final uci in widget.puzzle.moves) {
      try {
        final mv = NormalMove.fromUci(uci);
        pos = pos.play(mv);
        out.add(pos);
      } catch (_) {
        break;
      }
    }
    return out;
  }

  NormalMove? _currentMove() {
    if (_ply == 0) return null;
    return NormalMove.fromUci(widget.puzzle.moves[_ply - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final pos = _line[_ply];
    final playerSide = widget.puzzle.sideToMove == 'w' ? Side.white : Side.black;
    final orientation = _flipped
        ? (playerSide == Side.white ? Side.black : Side.white)
        : playerSide;
    final themes = widget.puzzle.themes;
    final explanation = widget.puzzle.explanation;
    return Focus(
      focusNode: _keyFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Analyze'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() => _ply = 0),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, outer) {
            // Reserve space for: theme chips (36) + optional explanation
            // (variable, approx 40 when present) + move strip (48) +
            // controls (56) + padding. Theme chips always shown; spec
            // requires them above the board in analyze mode.
            final hasExplanation = explanation != null && explanation.isNotEmpty;
            final reserved =
                36.0 + (hasExplanation ? 48.0 : 0.0) + 48.0 + 56.0 + 24.0;
            final boardSize =
                (outer.biggest.shortestSide.clamp(
                    200.0, outer.biggest.height - reserved))
                    .clamp(200.0, 1200.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Theme chips above the board (specs/hints-and-analyze.md).
                SizedBox(
                  height: 36,
                  child: Builder(builder: (_) {
                    if (themes.isEmpty) return const SizedBox.shrink();
                    final byId = ref.watch(themesProvider).maybeWhen(
                          data: (all) =>
                              {for (final t in all) t.id: t.displayName},
                          orElse: () => const <String, String>{},
                        );
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemBuilder: (_, i) => Chip(
                        label: Text(byId[themes[i]] ?? themes[i]),
                        visualDensity: VisualDensity.compact,
                      ),
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: 4),
                      itemCount: themes.length,
                    );
                  }),
                ),
                if (hasExplanation)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: Text(
                      explanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Center(
                  child: cg.StaticChessboard(
                    size: boardSize,
                    orientation: orientation,
                    fen: pos.fen,
                    lastMove: _currentMove(),
                    settings: cg.StaticChessboardSettings(
                      animationDuration:
                          MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                      showLastMove: true,
                    ),
                  ),
                ),
                _MoveStrip(
                  moves: widget.puzzle.moves,
                  currentPly: _ply,
                  onJump: (i) => setState(() => _ply = i),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed:
                            _ply > 0 ? () => setState(() => _ply -= 1) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: _ply < _line.length - 1
                            ? () => setState(() => _ply += 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

class _MoveStrip extends StatelessWidget {
  final List<String> moves;
  final int currentPly;
  final ValueChanged<int> onJump;

  const _MoveStrip({
    required this.moves,
    required this.currentPly,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (_, i) {
          final selected = currentPly == i + 1;
          return InputChip(
            label: Text(moves[i]),
            selected: selected,
            onPressed: () => onJump(i + 1),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemCount: moves.length,
      ),
    );
  }
}
