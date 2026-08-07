import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What just happened on the board.
enum BoardFxKind { success, failure }

/// Fires board flourishes from outside the widget tree.
///
/// The solve screen owns one of these and calls [fire] when a puzzle
/// resolves; [BoardFx] listens and runs the animation. Kept separate from
/// the widget so triggering an effect never means rebuilding the board.
class BoardFxController extends ChangeNotifier {
  BoardFxKind? kind;

  /// Where the interesting square is, in board fractions (0–1 from the
  /// top-left of the board as drawn). Null centres the effect.
  Offset? focus;

  /// Bumped on every fire so identical back-to-back effects still replay.
  int seq = 0;

  void fire(BoardFxKind kind, {Offset? at}) {
    this.kind = kind;
    focus = at;
    seq++;
    notifyListeners();
  }
}

/// Overlays a short flourish on the board: a particle burst and expanding
/// ring when a puzzle is solved, a shake and a red square flare when it is
/// missed.
///
/// Effects are decorative and never block: they run over the board, the
/// board stays interactive underneath, and the whole thing is skipped when
/// the platform asks for reduced motion.
class BoardFx extends StatefulWidget {
  const BoardFx({
    super.key,
    required this.size,
    required this.controller,
    required this.child,
  });

  /// Side length of the board this decorates.
  final double size;
  final BoardFxController controller;
  final Widget child;

  @override
  State<BoardFx> createState() => _BoardFxState();
}

class _BoardFxState extends State<BoardFx> with TickerProviderStateMixin {
  static const _burstDuration = Duration(milliseconds: 750);
  static const _shakeDuration = Duration(milliseconds: 420);

  late final AnimationController _burst;
  late final AnimationController _shake;

  List<_Particle> _particles = const [];
  Offset _focus = const Offset(0.5, 0.5);
  int _lastSeq = 0;

  @override
  void initState() {
    super.initState();
    // Eager, not lazy: a `late` controller first touched in dispose() would
    // build a ticker on a deactivated element.
    _burst = AnimationController(vsync: this, duration: _burstDuration);
    _shake = AnimationController(vsync: this, duration: _shakeDuration);
    widget.controller.addListener(_onFire);
  }

  @override
  void didUpdateWidget(BoardFx old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onFire);
      widget.controller.addListener(_onFire);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _burst.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onFire() {
    final c = widget.controller;
    if (c.seq == _lastSeq || !mounted) return;
    _lastSeq = c.seq;
    // Reduced motion means no decorative movement at all — the outcome is
    // already conveyed by the screen that follows.
    if (MediaQuery.of(context).disableAnimations) return;
    _focus = c.focus ?? const Offset(0.5, 0.5);
    if (c.kind == BoardFxKind.success) {
      _particles = _spawn(c.seq);
      _burst.forward(from: 0);
    } else {
      _shake.forward(from: 0);
    }
  }

  /// A ring of particles with randomised speed and angle, seeded off the
  /// fire count so consecutive bursts don't look identical.
  List<_Particle> _spawn(int seed) {
    final rnd = math.Random(seed);
    return List.generate(22, (i) {
      final angle = (i / 22) * 2 * math.pi + rnd.nextDouble() * 0.28;
      final speed = 0.22 + rnd.nextDouble() * 0.30;
      return _Particle(
        angle: angle,
        speed: speed,
        size: 1.6 + rnd.nextDouble() * 2.6,
        spin: rnd.nextDouble() * 0.5,
        color: [WR.green, WR.cyan, WR.amber][i % 3],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            if (!_shake.isAnimating) return child!;
            // Decaying horizontal wobble: fast at first, settling to nothing.
            final t = _shake.value;
            final decay = (1 - t) * (1 - t);
            final dx = math.sin(t * math.pi * 7) * 11 * decay;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_burst, _shake]),
              builder: (context, _) => CustomPaint(
                painter: _FxPainter(
                  burst: _burst.value,
                  burstActive: _burst.isAnimating,
                  shake: _shake.value,
                  shakeActive: _shake.isAnimating,
                  particles: _particles,
                  focus: _focus,
                  boardSize: widget.size,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
}

class _FxPainter extends CustomPainter {
  _FxPainter({
    required this.burst,
    required this.burstActive,
    required this.shake,
    required this.shakeActive,
    required this.particles,
    required this.focus,
    required this.boardSize,
  });

  final double burst;
  final bool burstActive;
  final double shake;
  final bool shakeActive;
  final List<_Particle> particles;
  final Offset focus;
  final double boardSize;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(focus.dx * size.width, focus.dy * size.height);
    final square = boardSize / 8;

    if (shakeActive) {
      // Red flare over the offending square, brightest immediately.
      final fade = (1 - shake).clamp(0.0, 1.0);
      final rect = Rect.fromCenter(
        center: origin,
        width: square,
        height: square,
      );
      canvas.drawRect(
        rect,
        Paint()..color = WR.red.withValues(alpha: 0.42 * fade),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = WR.red.withValues(alpha: 0.9 * fade),
      );
    }

    if (burstActive) {
      // Expanding ring, fading as it grows past the square it started on.
      final ringT = Curves.easeOutCubic.transform(burst.clamp(0.0, 1.0));
      final ringFade = (1 - burst).clamp(0.0, 1.0);
      canvas.drawCircle(
        origin,
        square * (0.45 + ringT * 2.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * ringFade
          ..color = WR.green.withValues(alpha: 0.75 * ringFade),
      );

      // Particles fly out and fall, shrinking as they fade.
      for (final p in particles) {
        final t = burst;
        final dist = p.speed * square * 5.2 * Curves.easeOutQuad.transform(t);
        final gravity = square * 2.4 * t * t;
        final pos = origin +
            Offset(math.cos(p.angle) * dist,
                math.sin(p.angle) * dist + gravity);
        final fade = (1 - t) * (1 - t * 0.4);
        canvas.drawCircle(
          pos,
          p.size * (1 - t * 0.55) * (1 + p.spin),
          Paint()..color = p.color.withValues(alpha: fade.clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) =>
      old.burst != burst ||
      old.shake != shake ||
      old.burstActive != burstActive ||
      old.shakeActive != shakeActive ||
      old.focus != focus;
}
