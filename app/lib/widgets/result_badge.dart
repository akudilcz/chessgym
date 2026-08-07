import 'package:flutter/material.dart';

/// The solved / missed icon at the top of the post-puzzle screen, arriving
/// with a spring and a halo that expands out of it.
///
/// A solve gets an overshooting pop; a miss gets a smaller, flatter one —
/// the outcome should be readable from the motion alone, before the text.
class ResultBadge extends StatefulWidget {
  const ResultBadge({
    super.key,
    required this.solved,
    required this.color,
    this.size = 72,
  });

  final bool solved;
  final Color color;
  final double size;

  @override
  State<ResultBadge> createState() => _ResultBadgeState();
}

class _ResultBadgeState extends State<ResultBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Created eagerly, not as a lazy `late` field: under reduce-motion the
    // build path never reads it, and dispose() would then be the first
    // access — constructing a ticker on an already-deactivated element.
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.solved ? 900 : 600),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.solved ? Icons.check_circle_outline : Icons.cancel_outlined,
      color: widget.color,
      size: widget.size,
    );
    if (MediaQuery.of(context).disableAnimations) return icon;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        // The pop settles in the first 45% of the run; the halo keeps
        // going after the icon has come to rest.
        final popT = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
        final scale = widget.solved
            ? 0.55 + 0.45 * popT
            : 0.85 + 0.15 * Curves.easeOutCubic
                .transform((t / 0.45).clamp(0.0, 1.0));
        return CustomPaint(
          painter: _HaloPainter(
            progress: t,
            color: widget.color,
            strong: widget.solved,
          ),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: icon,
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.progress,
    required this.color,
    required this.strong,
  });

  final double progress;
  final Color color;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final centre = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    // One ring for a miss, two staggered rings for a solve.
    final rings = strong ? const [0.0, 0.22] : const [0.0];
    for (final delay in rings) {
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final grown = Curves.easeOutCubic.transform(t);
      final fade = (1 - t) * (strong ? 0.7 : 0.45);
      canvas.drawCircle(
        centre,
        base * (0.7 + grown * 1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t) + 0.5
          ..color = color.withValues(alpha: fade.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.progress != progress || old.color != color || old.strong != strong;
}
