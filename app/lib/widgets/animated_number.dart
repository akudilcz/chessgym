import 'package:flutter/material.dart';

/// Tweens from the previous value → [value] whenever [value] changes.
/// Tabular digits so the width doesn't jitter mid-animation.
class AnimatedNumber extends StatefulWidget {
  final num value;
  final Duration duration;
  final int fractionDigits;
  final TextStyle? style;
  final String prefix;
  final String suffix;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 800),
    this.fractionDigits = 0,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  late num _from;
  late num _to;

  @override
  void initState() {
    super.initState();
    _from = 0;
    _to = widget.value;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = _currentValue();
      _to = widget.value;
      _ctrl.duration = widget.duration;
      _ctrl..reset()..forward();
    }
  }

  num _currentValue() {
    final t = _anim.value;
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatted(num v) {
    if (widget.fractionDigits > 0) {
      return v.toStringAsFixed(widget.fractionDigits);
    }
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the OS reduce-motion setting — skip the tween and show
    // the final value directly.
    if (MediaQuery.of(context).disableAnimations) {
      return Text(
        '${widget.prefix}${_formatted(widget.value)}${widget.suffix}',
        style: (widget.style ?? const TextStyle()).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        return Text(
          '${widget.prefix}${_formatted(_currentValue())}${widget.suffix}',
          style: (widget.style ?? const TextStyle()).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}
