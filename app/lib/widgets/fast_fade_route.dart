import 'package:flutter/material.dart';

/// Snappy fade transition used between solve → post-puzzle → solve. The
/// default Material slide felt heavy during the rapid play loop and
/// fought with the rating counter animation. 150 ms of fade keeps
/// the flow instant without being jarring.
class FastFadeRoute<T> extends PageRouteBuilder<T> {
  FastFadeRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          opaque: true,
          pageBuilder: (ctx, a1, a2) => builder(ctx),
          transitionsBuilder: (ctx, a, __, child) {
            // Respect the OS reduce-motion setting (specs/accessibility.md
            // — "piece-move animations collapse to instant state changes").
            if (MediaQuery.of(ctx).disableAnimations) return child;
            return FadeTransition(opacity: a, child: child);
          },
        );
}
