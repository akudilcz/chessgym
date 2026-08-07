import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress_service.dart';
import '../../data/providers.dart';
import '../../domain/rating_tier.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_number.dart';
import '../../widgets/live_dot.dart';
import '../../widgets/motion.dart';
import '../../widgets/tier_bar.dart';
import '../settings/settings_screen.dart';
import '../solve/solve_screen.dart';

/// War-room dashboard. No grid of decorative tiles — instead a HUD of
/// numerical stats and ranked lists of focus areas.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeyAsync = ref.watch(journeyProvider);
    return Scaffold(
      appBar: AppBar(
        // The tagline is decorative and the first thing that should give
        // way: unconstrained, this Row overflows on a 360dp phone, and by
        // ~290px at the Android maximum text scale.
        title: const Row(
          children: [
            LiveDot(color: WR.green, size: 8),
            SizedBox(width: 10),
            Flexible(
              child: Text('CHESS GYM', overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                '· WORKOUT THE MIND',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WR.muted,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: WR.muted),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              );
              ref.invalidate(journeyProvider);
            },
          ),
        ],
      ),
      body: journeyAsync.when(
        data: (j) => _Dashboard(snapshot: j),
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: WR.cyan),
              SizedBox(height: 18),
              Text('Warming up the puzzle library…',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: WR.muted,
                    fontSize: 12,
                    letterSpacing: 1.4,
                  )),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: WR.red)),
        ),
      ),
      floatingActionButton: journeyAsync.maybeWhen(
        data: (_) => _PlayButton(onPressed: () => _playNext(context, ref)),
        orElse: () => null,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _playNext(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SolveScreen(themeFocus: null)),
    );
    ref.invalidate(journeyProvider);
  }
}

/// The one button that matters. Its glow breathes so the eye is drawn back
/// to it, and it squashes under a press.
class _PlayButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _PlayButton({required this.onPressed});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const label = Padding(
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Text(
        'PLAY',
        style: TextStyle(
          fontFamily: 'monospace',
          color: WR.canvas,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 4.0,
        ),
      ),
    );
    // A forever-repeating animation never lets a test settle, and a
    // reduce-motion user asked for exactly this to stop.
    final reduced = MediaQuery.of(context).disableAnimations;

    return PressScale(
      onPressed: widget.onPressed,
      child: reduced
          ? _shell(24, 2, label)
          : AnimatedBuilder(
              animation: _glow,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_glow.value);
                return _shell(18 + 14 * t, 1 + 2.5 * t, child!);
              },
              child: label,
            ),
    );
  }

  Widget _shell(double blur, double spread, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: WR.cyan,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0x7700E5FF),
              blurRadius: blur,
              spreadRadius: spread,
            ),
          ],
        ),
        child: child,
      );
}

class _Dashboard extends StatelessWidget {
  final JourneySnapshot snapshot;
  const _Dashboard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    // Learning-state sections — consistent with a spaced-repetition /
    // desirable-difficulty model:
    //
    //   DUE NOW     — the theme has been practiced before and its
    //                 retention has faded below the 85% target; the
    //                 brain is about to forget, so re-drill.
    //   LEARNING    — in the 85% zone: recent practice, reasonable
    //                 clear rate, still building mastery.
    //   NEW         — untouched territory (no attempts) — explore.
    //   MASTERED    — cleared most / all attempts AND retention solid.
    //
    // Each section is sorted by the already-computed selection
    // probability (most-likely-next first).
    final dueNow = <ThemeProgress>[];
    final learning = <ThemeProgress>[];
    final newThemes = <ThemeProgress>[];
    final mastered = <ThemeProgress>[];

    for (final p in snapshot.themes) {
      final sr = p.successRate;
      final coldStart = p.attempts == 0;
      final clearMost = p.solved >= 5 && (sr == null || sr >= 0.90);
      final ratingMastered = p.mastery >= 0.80;
      final retainedWell = p.retrievability != null && p.retrievability! >= 0.85;

      if (coldStart) {
        newThemes.add(p);
      } else if (p.fading) {
        dueNow.add(p);
      } else if ((clearMost || ratingMastered) && retainedWell) {
        mastered.add(p);
      } else {
        learning.add(p);
      }
    }

    final children = <Widget>[
      _HudHeader(snapshot: snapshot),
      const SizedBox(height: 8),
    ];

    // TOP 5 — the five themes most likely to be served next, across
    // every bucket. Gives the player a one-glance "what should I work
    // on" without scanning the full list. Hidden when there's nothing
    // meaningful to highlight (cold start with zero selection
    // probability everywhere).
    final top5 = snapshot.themes
        .where((t) => t.selectionProbability > 0)
        .toList()
      ..sort((a, b) =>
          b.selectionProbability.compareTo(a.selectionProbability));
    if (top5.isNotEmpty) {
      children.add(_ThemePanel(
        title: 'TOP 5',
        subtitle: 'Your next few puzzles likely come from here',
        accent: WR.amber,
        rows: top5.take(5).toList(),
        emptyMsg: '',
        info:
            'The five themes most likely to be served on your next PLAY tap. '
            'Mix of any REVIEW, PRACTICE, or UNEXPLORED themes the selector '
            'favours right now. Percentages sum close to 1.00 across this list.',
      ));
      children.add(const SizedBox(height: 6));
    }

    // REVIEW only when there's something to see (fading themes appear
    // after you've practiced, then been away long enough for retention
    // to drop below 85%). Shown with the same hide-when-empty pattern
    // as NEW and MASTERED.
    if (dueNow.isNotEmpty) {
      children.add(_ThemePanel(
        title: 'REVIEW',
        subtitle: 'Review before you forget',
        accent: WR.amber,
        rows: dueNow,
        emptyMsg: '',
        info:
            'Themes you have practised before, now fading from memory '
            '(retention below 85%). Re-drill these to lock them in. '
            '30% of next puzzles come from this bucket when non-empty.',
      ));
      children.add(const SizedBox(height: 6));
    }
    // PRACTICE — always shown (primary section mid-session).
    children.add(_ThemePanel(
      title: 'PRACTICE',
      subtitle: 'Working on these right now',
      accent: WR.cyan,
      rows: learning,
      emptyMsg: '—',
      info:
          'Themes you are actively learning. You have attempted some of '
          'them, still hitting mixed results or climbing your rating. '
          'The bulk of your next puzzles come from here.',
    ));
    // NEW and MASTERED: hide the entire section when empty — nothing to
    // tell the player in that state, and hiding shortens the page.
    if (newThemes.isNotEmpty) {
      children.add(const SizedBox(height: 6));
      children.add(_ThemePanel(
        title: 'UNEXPLORED',
        subtitle: "Haven't tried yet",
        accent: WR.violet,
        rows: newThemes,
        emptyMsg: '',
        info:
            'Themes you have never attempted. The selector samples these '
            'occasionally to broaden your training — over time every theme '
            'moves into PRACTICE once you engage with it.',
      ));
    }
    if (mastered.isNotEmpty) {
      children.add(const SizedBox(height: 6));
      children.add(_ThemePanel(
        title: 'MASTERED',
        subtitle: 'Consistently solving these',
        accent: WR.green,
        rows: mastered,
        emptyMsg: '',
        info:
            'Themes you consistently clear, with retention above 85%. '
            'They resurface only when your retention model predicts you '
            'are about to forget — FSRS-style spaced repetition.',
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 100),
      // Panels assemble top-down rather than all landing at once.
      children: [
        for (var i = 0; i < children.length; i++)
          Entrance(index: i, child: children[i]),
      ],
    );
  }
}

class _HudHeader extends StatelessWidget {
  final JourneySnapshot snapshot;
  const _HudHeader({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final g = snapshot.globalRating;
    final disp = displayRating(g.rating);
    final tier = tierFor(disp.toDouble());
    final xp = snapshot.xp;
    final xpAt = snapshot.xpAtLevel;
    final xpTo = snapshot.xpAtNextLevel;
    final xpFrac = xpTo > xpAt ? (xp - xpAt) / (xpTo - xpAt) : 0.0;
    // Clear rate = distinct solved / distinct seen, matching the player's
    // mental model: "of the puzzles I've seen, how many did I solve?".
    // Counting total attempts instead would make a puzzle you failed and
    // then solved lower your accuracy. (Summing solved + missed here would
    // double-count a puzzle that was solved once but failed most recently.)
    final distinctSeen = snapshot.distinctSeen;
    final acc = distinctSeen == 0
        ? 0.0
        : (snapshot.totalSolved / distinctSeen).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: WR.panel,
        border: Border.all(color: WR.divider),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(builder: (ctx, cons) {
        final narrow = cons.maxWidth < 520; // phone breakpoint
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HERO: big rating + tier, centered for phone.
            _HeroRating(
              rating: disp,
              rd: g.rd.round(),
              tierColor: tier.color,
              tierLabel: tier.label.toUpperCase(),
            ),
            const SizedBox(height: 10),
            TierBar(displayedRating: disp),
            const SizedBox(height: 12),
            _XpLine(
              level: snapshot.level,
              xp: xp,
              xpTo: xpTo,
              frac: xpFrac.clamp(0.0, 1.0),
            ),
            const SizedBox(height: 10),
            // Secondary stats — 4 tiles in a Wrap so they flow on phone.
            _StatTiles(
              narrow: narrow,
              tiles: [
                _Tile(
                  label: 'SOLVED',
                  value: '${snapshot.totalSolved}',
                  color: WR.green,
                  info:
                      'Distinct puzzles you have solved at least once. Re-solves don\'t double-count.',
                ),
                _Tile(
                  label: 'ACCURACY',
                  value: '${(acc * 100).round()}%',
                  color: WR.cyan,
                  info:
                      'First-try success rate across all attempted puzzles.',
                ),
                _Tile(
                  label: 'MISSED',
                  value: '${snapshot.missedCount}',
                  color: snapshot.missedCount == 0 ? WR.green : WR.red,
                  info:
                      'Puzzles whose last outcome was a miss. They resurface until cleared. Goal: drive this to zero.',
                ),
                _Tile(
                  label: 'LEVEL',
                  value: '${snapshot.level}',
                  color: WR.amber,
                  info:
                      'Cumulative practice level. Every attempt earns XP; every solve earns more.',
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Centered hero: big rating number, ±RD below, tier label below that.
class _HeroRating extends StatelessWidget {
  final int rating;
  final int rd;
  final Color tierColor;
  final String tierLabel;
  const _HeroRating({
    required this.rating,
    required this.rd,
    required this.tierColor,
    required this.tierLabel,
  });

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WR.panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tierColor),
          borderRadius: BorderRadius.circular(6),
        ),
        title: Row(
          children: [
            LiveDot(color: tierColor, size: 7),
            const SizedBox(width: 8),
            Text('RATING',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: tierColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                )),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Your current chess strength on the international scale. '
              'Updates after every puzzle via the Glicko-2 rating system '
              '— the same algorithm Lichess uses.',
              style: TextStyle(color: WR.text, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              'The ±number next to the rating is the rating deviation '
              '(RD). The system is ~68% confident your true rating is '
              'within that range. RD shrinks as you play and grows '
              'during long breaks.',
              style: TextStyle(color: WR.text, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              'The tier label below the number (BEGINNER, NOVICE, …) '
              'is a fixed band based on rating alone. Tier thresholds '
              'mirror the international scale used across online chess.',
              style: TextStyle(color: WR.text, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showInfo(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(
                  value: rating,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: tierColor,
                    height: 1.0,
                    shadows: [
                      Shadow(
                          color: tierColor.withValues(alpha: 0.5),
                          blurRadius: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '±$rd',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: tierColor.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.info_outline,
                    size: 14, color: tierColor.withValues(alpha: 0.7)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LiveDot(color: tierColor, size: 6),
                const SizedBox(width: 6),
                Text(
                  tierLabel,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: tierColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _XpLine extends StatelessWidget {
  final int level;
  final int xp;
  final int xpTo;
  final double frac;
  const _XpLine({
    required this.level,
    required this.xp,
    required this.xpTo,
    required this.frac,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'L$level',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: WR.amber,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  backgroundColor: WR.divider,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(WR.amber),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$xp / $xpTo',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: WR.muted,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tile {
  final String label;
  final String value;
  final Color color;
  final String info;
  const _Tile({
    required this.label,
    required this.value,
    required this.color,
    required this.info,
  });
}

class _StatTiles extends StatelessWidget {
  final bool narrow;
  final List<_Tile> tiles;
  const _StatTiles({required this.narrow, required this.tiles});

  @override
  Widget build(BuildContext context) {
    // 4 tiles in 2 columns on phone, one row on wider screens.
    return LayoutBuilder(builder: (ctx, cons) {
      final cols = narrow ? 2 : tiles.length;
      final gap = 8.0;
      final tileWidth = (cons.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: tiles
            .map((t) => SizedBox(
                  width: tileWidth,
                  child: _TileView(tile: t),
                ))
            .toList(),
      );
    });
  }
}

class _TileView extends StatelessWidget {
  final _Tile tile;
  const _TileView({required this.tile});

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WR.panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tile.color),
          borderRadius: BorderRadius.circular(6),
        ),
        title: Row(
          children: [
            LiveDot(color: tile.color, size: 7),
            const SizedBox(width: 8),
            Text(tile.label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: tile.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                )),
          ],
        ),
        content: Text(tile.info,
            style: const TextStyle(color: WR.text, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showInfo(context),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WR.canvas,
        border: Border.all(color: WR.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              LiveDot(color: tile.color, size: 5),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: WR.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              tile.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                color: tile.color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ThemePanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color accent;
  final List<ThemeProgress> rows;
  final String emptyMsg;
  final String info;
  const _ThemePanel({
    required this.title,
    this.subtitle,
    required this.accent,
    required this.rows,
    required this.emptyMsg,
    required this.info,
  });

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WR.panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent),
          borderRadius: BorderRadius.circular(6),
        ),
        title: Row(
          children: [
            Container(width: 3, height: 14, color: accent),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                )),
          ],
        ),
        content: Text(info,
            style: const TextStyle(color: WR.text, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WR.panel,
        border: Border.all(color: WR.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header strip — compact single-line.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: WR.divider)),
              color: accent.withValues(alpha: 0.05),
            ),
            child: Row(
              children: [
                Container(
                    width: 3, height: 11, color: accent,
                    margin: const EdgeInsets.only(right: 6)),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: WR.muted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                // A bare GestureDetector produces no semantics node, so this
                // control was invisible to screen readers AND to the
                // tap-target guidelines — a 14px icon that nothing flagged.
                // IconButton carries the button role, a label, and a 48dp
                // target while the glyph stays visually small.
                IconButton(
                  onPressed: () => _showInfo(context),
                  icon: Icon(Icons.info_outline,
                      size: 14, color: accent.withValues(alpha: 0.75)),
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: 'About this panel',
                ),
              ],
            ),
          ),
          // Rows.
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                emptyMsg,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: WR.muted,
                  fontSize: 11,
                  letterSpacing: 1.4,
                ),
              ),
            )
          else
            ...List.generate(rows.length, (i) {
              final p = rows[i];
              return _ThemeRow(row: p, index: i, accent: accent);
            }),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ThemeProgress row;
  final int index;
  final Color accent;
  const _ThemeRow({required this.row, required this.index, required this.accent});

  Color _probColor(double p) {
    if (p >= 0.20) return WR.amber;
    if (p >= 0.05) return WR.cyan;
    return WR.muted;
  }

  @override
  Widget build(BuildContext context) {
    final successPct =
        row.attempts == 0 ? null : row.solved / row.attempts;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: WR.divider.withValues(alpha: 0.5)),
        ),
      ),
      // Compact row: index · name · (fading) · selection% · success%.
      // Removed solved/total count and the wide horizontal progress bar
      // per user feedback — name needs the breathing room on a phone.
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              index.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: WR.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.theme.displayName.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: WR.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (row.fading)
            const Padding(
              padding: EdgeInsets.only(left: 6, right: 2),
              child: Tooltip(
                message: 'Retention fading — due for re-drill',
                child: Icon(Icons.hourglass_bottom_rounded,
                    size: 12, color: WR.amber),
              ),
            ),
          SizedBox(
            width: 56,
            child: Text(
              row.selectionProbability <= 0
                  ? ' — '
                  : '${(row.selectionProbability * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                color: _probColor(row.selectionProbability),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              successPct == null ? ' — ' : '${(successPct * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                color: successPct == null
                    ? WR.muted
                    : (successPct < 0.5
                        ? WR.red
                        : (successPct < 0.75 ? WR.amber : WR.green)),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
