import 'package:flutter/material.dart';

import '../../data/prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/live_dot.dart';

/// First-run 3-slide intro. Sets Prefs.kOnboardingSeen on completion.
class OnboardingScreen extends StatefulWidget {
  final Prefs prefs;
  final VoidCallback onDone;
  const OnboardingScreen({
    super.key,
    required this.prefs,
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      title: 'CHESS GYM',
      subtitle: 'Workout the mind.',
      bullets: [
        'Curated chess puzzles, not random ones.',
        'Adaptive — the app finds your weakest tactical areas and trains you there.',
        'Offline. No accounts. No ads. No telemetry.',
      ],
      icon: Icons.fitness_center_rounded,
      color: WR.cyan,
    ),
    _Slide(
      title: 'THE HUD',
      subtitle: 'Your mission-control dashboard.',
      bullets: [
        'RATING — your Glicko-2 rating with ± uncertainty. Tap it for an explanation.',
        'LEVEL + XP — every attempt earns XP, every solve earns more.',
        'TOP 5 — the five themes the selector is most likely to serve you next.',
        'MISSED — puzzles you\'ve failed; drive this to zero for 100% clear.',
      ],
      icon: Icons.insights_rounded,
      color: WR.amber,
    ),
    _Slide(
      title: 'THE LOOP',
      subtitle: 'Tap PLAY. Solve. Repeat.',
      bullets: [
        'One puzzle at a time. The app picks the theme for you, biased toward whatever you need most right now.',
        'Fading themes get a 30% share so you re-drill before forgetting; fresh themes surface quickly.',
        'Failed puzzles come back later — and you can revisit any time.',
        'When you\'re stuck, tap Analyze after the fact to see the full solution.',
      ],
      icon: Icons.play_arrow_rounded,
      color: WR.green,
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.prefs.setBool(Prefs.kOnboardingSeen, true);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const LiveDot(color: WR.green, size: 8),
                  const SizedBox(width: 8),
                  const Text('CHESS GYM',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: WR.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      )),
                  const Spacer(),
                  if (_page < _slides.length - 1)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('SKIP'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            _Dots(count: _slides.length, index: _page),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton.icon(
                      onPressed: () => _pc.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('BACK'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      if (_page == _slides.length - 1) {
                        _finish();
                      } else {
                        _pc.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut);
                      }
                    },
                    icon: Icon(_page == _slides.length - 1
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded),
                    label: Text(
                        _page == _slides.length - 1 ? 'PLAY' : 'NEXT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String title;
  final String subtitle;
  final List<String> bullets;
  final IconData icon;
  final Color color;
  const _Slide({
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.icon,
    required this.color,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(slide.icon, size: 72, color: slide.color),
          const SizedBox(height: 20),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              color: slide.color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slide.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WR.muted,
              fontSize: 14,
              fontFamily: 'monospace',
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 28),
          ...slide.bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chevron_right_rounded,
                      color: slide.color, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                          color: WR.text, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == index ? WR.cyan : WR.divider,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
