import 'package:flutter/material.dart';

import '../../domain/app_info.dart';
import '../../theme/app_theme.dart';

/// War-room-styled About dialog with a full credit roll.
Future<void> showAboutPopup(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (_) => const _AboutBody(),
  );
}

class _AboutBody extends StatelessWidget {
  const _AboutBody();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WR.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: WR.cyan, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 3, height: 18, color: WR.cyan),
                  const SizedBox(width: 8),
                  const Text(
                    'CHESS GYM',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: WR.cyan,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: WR.muted),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'VERSION ${AppInfo.version}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: WR.muted,
                  fontSize: 11,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: WR.divider, height: 1),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      _SectionHeader('TAGLINE'),
                      _Body(
                          "A workout for the mind. War-room chess puzzle "
                          "trainer. No ads. No accounts. No telemetry. "
                          "Fully offline."),
                      _SectionHeader('PUZZLE DATA'),
                      _Credit(
                        who: 'Lichess.org',
                        what: 'puzzle database',
                        license: 'CC0 1.0 Universal',
                        note:
                            'Curated from the open Lichess puzzle database '
                            '(~6M puzzles total), scored for interest and '
                            'stratified by theme and rating.',
                      ),
                      _SectionHeader('OPEN SOURCE LIBRARIES'),
                      _Credit(
                        who: 'Lichess',
                        what: 'dartchess',
                        license: 'GPL-3.0',
                        note:
                            'Chess rules engine (move generation, legality, FEN/PGN).',
                      ),
                      _Credit(
                        who: 'Lichess',
                        what: 'chessground (Flutter)',
                        license: 'GPL-3.0',
                        note: 'Interactive board widget with animations and drag-to-move.',
                      ),
                      _Credit(
                        who: 'Alexandre Roux (Tekartik)',
                        what: 'sqflite',
                        license: 'BSD 2-Clause',
                        note: 'SQLite plugin for Flutter.',
                      ),
                      _Credit(
                        who: 'Remi Rousselet',
                        what: 'flutter_riverpod',
                        license: 'MIT',
                        note: 'State management.',
                      ),
                      _Credit(
                        who: 'Marcelo Glasberg',
                        what: 'fast_immutable_collections',
                        license: 'BSD 2-Clause',
                        note: 'Immutable IMap / ISet used by chessground.',
                      ),
                      _SectionHeader('ASSETS'),
                      _Credit(
                        who: 'Colin M.L. Burnett',
                        what: 'Cburnett SVG chess pieces',
                        license: 'CC-BY-SA 3.0',
                        note:
                            'Default piece set via chessground. Wikimedia Commons.',
                      ),
                      _SectionHeader('ALGORITHMS & RESEARCH'),
                      _Credit(
                        who: 'Mark Glickman',
                        what: 'Glicko-2 rating system',
                        license: 'Algorithmic (research paper)',
                        note:
                            'Implementation verified against Glickman (2013) worked example.',
                      ),
                      _Credit(
                        who: 'Open Spaced Repetition',
                        what: 'FSRS-4',
                        license: 'MIT (reference impl)',
                        note:
                            'Ported to pure Dart for offline review scheduling.',
                      ),
                      _Credit(
                        who: 'Azlan Iqbal (AAAI 2006) et al.',
                        what: 'chess aesthetics scoring',
                        license: 'Research (not code)',
                        note:
                            'Interestingness-ranking formula for the pipeline.',
                      ),
                      _SectionHeader('BUILD-TIME ONLY'),
                      _Credit(
                        who: 'Niklas Fiekas',
                        what: 'python-chess',
                        license: 'GPL-3.0',
                        note:
                            'Used only by the pipeline that produces puzzles.sqlite. '
                            'Not shipped with the app.',
                      ),
                      _SectionHeader('APP LICENSE'),
                      _Body(
                          'Chess Gym app code is GPL-3.0 — transitively required by '
                          'dartchess and chessground (both GPL-3.0).'),
                      _SectionHeader('PRIVACY'),
                      _Body(
                          'This app collects no data. All progress is stored on your '
                          'device. No accounts, no analytics, no ads, no third-party '
                          'SDKs, no network requests at runtime.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: WR.divider, height: 1),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CLOSE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Container(width: 3, height: 12, color: WR.cyan),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: WR.cyan,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: SelectableText(
        text,
        style: const TextStyle(
          color: WR.text,
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  final String who;
  final String what;
  final String license;
  final String note;
  const _Credit({
    required this.who,
    required this.what,
    required this.license,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontFamily: 'monospace', color: WR.text, fontSize: 12.5),
              children: [
                TextSpan(
                  text: what,
                  style: const TextStyle(
                      color: WR.amber, fontWeight: FontWeight.w800),
                ),
                TextSpan(text: '  ·  ', style: const TextStyle(color: WR.muted)),
                TextSpan(text: who),
                const TextSpan(text: '   '),
                TextSpan(
                  text: '[$license]',
                  style: const TextStyle(
                      color: WR.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              note,
              style: const TextStyle(
                color: WR.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
