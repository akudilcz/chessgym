import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/app_info.dart';
import '../theme/app_theme.dart';

/// Shows the version and build number over the app for a few seconds after
/// launch, then fades away.
///
/// Without this there is no way to tell which APK is actually installed:
/// the version string alone is identical across builds, so a stale download
/// looks exactly like a fresh one. The build number is the CI run number,
/// matching the release title on GitHub.
///
/// Purely informational — it never blocks input, and it is announced to
/// screen readers rather than being silently decorative.
class VersionFlash extends StatefulWidget {
  const VersionFlash({
    super.key,
    required this.child,
    this.visibleFor = const Duration(seconds: 4),
  });

  final Widget child;

  /// How long the badge stays at full opacity before fading out.
  final Duration visibleFor;

  @override
  State<VersionFlash> createState() => _VersionFlashState();
}

class _VersionFlashState extends State<VersionFlash> {
  bool _show = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.visibleFor, () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          // Clear of the centre-floating PLAY button, which lives in the
          // bottom 70-odd pixels of the dashboard.
          bottom: 96,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: WR.panelElev.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: WR.divider),
                  ),
                  child: Text(
                    'v${AppInfo.fullVersion}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: WR.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
