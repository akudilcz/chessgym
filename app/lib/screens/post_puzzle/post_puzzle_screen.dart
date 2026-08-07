import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/player_db.dart';
import '../../data/prefs.dart';
import '../../data/providers.dart';
import '../../domain/puzzle.dart';
import '../../domain/rating_tier.dart';
import '../../widgets/fast_fade_route.dart';
import '../analyze/analyze_screen.dart';
import '../solve/solve_screen.dart';

/// Result screen with a short auto-advance timer to the next puzzle — the
/// game loop favours flow over friction. The player can tap Analyze or
/// Dashboard to break the loop at any time.
class PostPuzzleScreen extends ConsumerStatefulWidget {
  final Puzzle puzzle;
  final bool solved;
  final double ratingDelta;

  const PostPuzzleScreen({
    super.key,
    required this.puzzle,
    required this.solved,
    required this.ratingDelta,
  });

  @override
  ConsumerState<PostPuzzleScreen> createState() => _PostPuzzleScreenState();
}

class _PostPuzzleScreenState extends ConsumerState<PostPuzzleScreen> {
  Duration? _autoAdvance;
  bool _advanced = false;
  Timer? _autoAdvanceTimer;

  /// Memoized: building this future inline in build() re-queried the stats
  /// on every rebuild (each async provider resolution), flickering the
  /// history box through its null frame.
  late final Future<PuzzleStats?> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref
        .read(playerDbProvider.future)
        .then((pdb) => pdb.puzzleStats(widget.puzzle.id));
    _setupAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _setupAutoAdvance() async {
    final prefs = await ref.read(prefsProvider.future);
    if (!mounted) return;
    final ms = prefs.getInt(Prefs.kAutoAdvanceMs, defaultValue: Prefs.kAutoAdvanceDefaultMs);
    if (ms <= 0) {
      setState(() => _autoAdvance = null);
      return;
    }
    setState(() => _autoAdvance = Duration(milliseconds: ms));
    _autoAdvanceTimer = Timer(_autoAdvance!, () {
      if (!mounted || _advanced) return;
      // Only advance if this screen is still the one being looked at.
      // Tapping Analyze pushes a route on top without setting _advanced,
      // and pushReplacement replaces the TOPMOST route — so this would
      // yank the analysis away mid-read and strand a dead route beneath.
      // The countdown is spent either way, so hide the bar rather than
      // leave an expired ticker that will never advance.
      if (ModalRoute.of(context)?.isCurrent == false) {
        setState(() => _autoAdvance = null);
        return;
      }
      _advanceToNext();
    });
  }

  // solve_screen._finish already invalidates journeyProvider and
  // globalRatingProvider immediately after writing the attempt, so we
  // don't re-invalidate here — doing so forced a redundant second
  // snapshot rebuild on every navigation out of this screen.

  void _advanceToNext() {
    if (_advanced) return;
    _advanced = true;
    Navigator.of(context).pushReplacement(
      FastFadeRoute(
        builder: (_) => const SolveScreen(themeFocus: null),
      ),
    );
  }

  void _goDashboard() {
    if (_advanced) return;
    _advanced = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final puzzle = widget.puzzle;
    final solved = widget.solved;
    final ratingDelta = widget.ratingDelta;
    final scheme = Theme.of(context).colorScheme;
    final resultColor = solved ? Colors.green.shade600 : Colors.red.shade600;
    // When we land here, the global rating has already been persisted for
    // this attempt, so globalRatingProvider reflects the NEW rating.
    final journeyAsync = ref.watch(journeyProvider);
    final ratingAsync = ref.watch(globalRatingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(solved ? 'Solved' : 'Missed'),
        backgroundColor: resultColor.withValues(alpha: 0.08),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Icon(
                          solved
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                          color: resultColor,
                          size: 72,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Animated rating counter.
                      Center(
                        child: ratingAsync.maybeWhen(
                          data: (g) => _AnimatedRating(
                            // Convert to displayed (international) scale.
                            ending: g.rating - 300,
                            delta: ratingDelta,
                          ),
                          orElse: () => const SizedBox(height: 48),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (puzzle.originLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(puzzle.originLabel!,
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center),
                        ),
                      if (puzzle.explanation != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(puzzle.explanation!,
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center),
                        ),
                      // Render theme chips with display names when we can
                      // resolve them; fall back to the raw id so a theme
                      // missing from the index (shouldn't happen) doesn't
                      // leave a gap.
                      Consumer(builder: (ctx, ref, _) {
                        final themesAsync = ref.watch(themesProvider);
                        final byId = themesAsync.maybeWhen(
                          data: (all) => {for (final t in all) t.id: t},
                          orElse: () => const <String, dynamic>{},
                        );
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: puzzle.themes.map((t) {
                            final info = byId[t];
                            final label =
                                info is ThemeInfo ? info.displayName : t;
                            return Chip(label: Text(label));
                          }).toList(),
                        );
                      }),
                      const SizedBox(height: 12),
                      // Your history on THIS puzzle.
                      FutureBuilder<PuzzleStats?>(
                        future: _statsFuture,
                        builder: (ctx, snap) {
                          final s = snap.data;
                          if (s == null || s.attempts == 0) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: _TinyStat(
                                        label: 'ATTEMPTS',
                                        value: '${s.attempts}')),
                                Expanded(
                                    child: _TinyStat(
                                        label: 'SOLVED',
                                        value: '${s.solves}')),
                                Expanded(
                                    child: _TinyStat(
                                        label: 'FAILED',
                                        value: '${s.fails}')),
                                Expanded(
                                    child: _TinyStat(
                                        label: 'AVG TIME',
                                        value: _formatDuration(
                                            s.avgDurationMs))),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Per-theme progress bars — show how many puzzles solved
                      // in each theme this puzzle belongs to, so the user
                      // sees exactly what just incremented.
                      journeyAsync.maybeWhen(
                        data: (j) {
                          final relevantThemes =
                              j.themes.where((p) => puzzle.themes.contains(p.theme.id));
                          if (relevantThemes.isEmpty) return const SizedBox();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: relevantThemes.map((p) {
                              final frac =
                                  p.total == 0 ? 0.0 : p.solved / p.total;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          p.theme.displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${p.solved} / ${p.total}',
                                          style: TextStyle(
                                            color: scheme.primary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: frac.clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor: scheme.primary
                                            .withValues(alpha: 0.15),
                                        valueColor: AlwaysStoppedAnimation(
                                            scheme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                        orElse: () => const SizedBox(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Icon-only secondary actions keep the row legible on narrow
              // phones; Next is the primary action and gets the label.
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Analyze',
                    icon: const Icon(Icons.search),
                    onPressed: () => Navigator.of(context).push(
                      FastFadeRoute(
                        builder: (_) => AnalyzeScreen(puzzle: puzzle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Dashboard',
                    icon: const Icon(Icons.dashboard_rounded),
                    onPressed: _goDashboard,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _advanceToNext,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Next'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Auto-advance ticker — visual hint that we'll progress on
              // our own. Tap any button to skip. Omit when disabled.
              if (_autoAdvance != null)
                _AutoAdvanceBar(duration: _autoAdvance!),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDuration(double? ms) {
  if (ms == null) return '—';
  final secs = (ms / 1000).round();
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

class _TinyStat extends StatelessWidget {
  final String label;
  final String value;
  const _TinyStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  letterSpacing: 1.3)),
        ),
      ],
    );
  }
}

/// Visual countdown until auto-advance to the next puzzle. Gives the player
/// a reason to stick with the keyboard-free flow without being surprised.
class _AutoAdvanceBar extends StatefulWidget {
  final Duration duration;
  const _AutoAdvanceBar({required this.duration});

  @override
  State<_AutoAdvanceBar> createState() => _AutoAdvanceBarState();
}

class _AutoAdvanceBarState extends State<_AutoAdvanceBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: 1 - _ctrl.value,
            minHeight: 3,
            backgroundColor: scheme.primary.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              scheme.primary.withValues(alpha: 0.6),
            ),
          ),
        );
      },
    );
  }
}

/// Animated rating counter: tweens from (end-delta) → end over 600ms with a
/// big delta badge that glows.
class _AnimatedRating extends StatefulWidget {
  final double ending;
  final double delta;
  const _AnimatedRating({required this.ending, required this.delta});

  @override
  State<_AnimatedRating> createState() => _AnimatedRatingState();
}

class _AnimatedRatingState extends State<_AnimatedRating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.ending - widget.delta;
    final tier = tierFor(widget.ending);
    // Respect the OS reduce-motion setting — show the final rating and
    // delta instantly instead of tweening.
    final reduced = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final t = reduced ? 1.0 : _anim.value;
        final shown = start + widget.delta * t;
        final deltaShown = widget.delta * t;
        final deltaColor =
            widget.delta >= 0 ? Colors.green.shade700 : Colors.red.shade700;
        return Column(
          children: [
            Text(
              shown.round().toString(),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: tier.color,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tier.icon, size: 18, color: tier.color),
                const SizedBox(width: 6),
                Text(
                  tier.label,
                  style: TextStyle(
                      color: tier.color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 14),
                Text(
                  widget.delta >= 0
                      ? '+${deltaShown.toStringAsFixed(1)}'
                      : deltaShown.toStringAsFixed(1),
                  style: TextStyle(
                    color: deltaColor,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
