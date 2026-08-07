import 'package:flutter/material.dart';

/// Fades and lifts a widget into place, staggered by [index].
///
/// Used for dashboard panels so the screen assembles itself top-down
/// instead of appearing all at once. The stagger is capped so a long list
/// never leaves the last panel waiting.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.index,
    required this.child,
    this.stagger = const Duration(milliseconds: 45),
    this.maxDelay = const Duration(milliseconds: 400),
  });

  final int index;
  final Widget child;
  final Duration stagger;
  final Duration maxDelay;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 320);

  late final AnimationController _ctrl;
  late final Curve _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.stagger.inMilliseconds * widget.index)
        .clamp(0, widget.maxDelay.inMilliseconds);
    final totalMs = delayMs + _fade.inMilliseconds;
    // The stagger is an interval inside one controller rather than a
    // Future.delayed: a pending timer outlives the widget and fails tests
    // at teardown, while a ticker is owned by this State.
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _curve = Interval(delayMs / totalMs, 1.0, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start here, not in initState: MediaQuery is only reliable once
    // dependencies are resolved, and a reduce-motion user should never have
    // a ticker running at all.
    if (_started) return;
    _started = true;
    if (!MediaQuery.of(context).disableAnimations) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _curve.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child:
              Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Shrinks slightly while held, so taps feel physical rather than instant.
///
/// Wraps the gesture itself: [onPressed] fires on tap-up, and the scale
/// springs back whether the press was completed or cancelled.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onPressed,
    this.scale = 0.94,
  });

  final Widget child;
  final VoidCallback onPressed;

  /// How far down to squash while held.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
