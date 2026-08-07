import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder shown while a puzzle loads: an empty board with a sheen
/// sweeping across it.
///
/// A bare spinner made the most-visited screen in the app feel like it was
/// stalling. A board-shaped skeleton says what is coming and holds the
/// layout, so nothing jumps when the real board arrives.
class BoardSkeleton extends StatefulWidget {
  const BoardSkeleton({super.key, this.size = 320});

  final double size;

  @override
  State<BoardSkeleton> createState() => _BoardSkeletonState();
}

class _BoardSkeletonState extends State<BoardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A repeating ticker would never let a widget test settle, and a
    // reduce-motion user asked for stillness.
    if (_started) return;
    _started = true;
    if (!MediaQuery.of(context).disableAnimations) _sheen.repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading puzzle',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _sheen,
          builder: (context, _) => CustomPaint(
            painter: _SkeletonPainter(
              sweep: _sheen.value,
              sweeping: _sheen.isAnimating,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({required this.sweep, required this.sweeping});

  final double sweep;
  final bool sweeping;

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / 8;
    final light = Paint()..color = WR.panelElev;
    final dark = Paint()..color = WR.panel;

    for (var rank = 0; rank < 8; rank++) {
      for (var file = 0; file < 8; file++) {
        canvas.drawRect(
          Rect.fromLTWH(file * square, rank * square, square, square),
          (rank + file).isEven ? light : dark,
        );
      }
    }

    if (sweeping) {
      // A soft diagonal band travelling from one corner to the other.
      final x = (sweep * 2 - 0.5) * size.width;
      final band = Rect.fromLTWH(x - size.width * 0.35, 0,
          size.width * 0.7, size.height);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              WR.cyan.withValues(alpha: 0.0),
              WR.cyan.withValues(alpha: 0.10),
              WR.cyan.withValues(alpha: 0.0),
            ],
          ).createShader(band),
      );
    }

    // A thin frame so it reads as a board rather than a grey block.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = WR.divider,
    );
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.sweep != sweep || old.sweeping != sweeping;
}
