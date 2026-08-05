import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs.dart';
import '../../data/providers.dart';
import '../../domain/app_info.dart';
import '../../theme/app_theme.dart';
import 'about_dialog.dart' as about;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Prefs? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ref.read(prefsProvider.future);
    if (!mounted) return;
    setState(() => _prefs = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS')),
      body: p == null
          ? const Center(child: CircularProgressIndicator(color: WR.cyan))
          : ListView(
              children: [
                _Section(title: 'FEEDBACK'),
                SwitchListTile(
                  title: const Text('Haptics'),
                  subtitle: const Text('Vibration on move and outcome'),
                  value: p.getBool(Prefs.kHapticsOn, defaultValue: true),
                  onChanged: (v) async {
                    await p.setBool(Prefs.kHapticsOn, v);
                    setState(() {});
                  },
                ),
                _Section(title: 'FLOW'),
                ListTile(
                  title: const Text('Auto-advance after puzzle'),
                  subtitle: Text(_autoAdvanceLabel(
                      p.getInt(Prefs.kAutoAdvanceMs, defaultValue: Prefs.kAutoAdvanceDefaultMs))),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAutoAdvanceDialog(p),
                ),
                _Section(title: 'DATA'),
                ListTile(
                  title: const Text('Reset progress'),
                  subtitle:
                      const Text('Wipes all ratings, reviews, and history.'),
                  trailing: const Icon(Icons.warning_amber_outlined,
                      color: WR.amber),
                  onTap: () => _confirmReset(context),
                ),
                _Section(title: 'ABOUT'),
                const ListTile(
                  title: Text('Privacy'),
                  subtitle: Text(
                      'This app collects no data. All progress is stored on '
                      'your device. No accounts, no analytics, no ads, no '
                      'network calls.'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: WR.cyan),
                  title: const Text('About Chess Gym'),
                  subtitle: const Text(
                      'Version, credits, attribution, and licenses'),
                  onTap: () => about.showAboutPopup(context),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined, color: WR.cyan),
                  title: const Text('Open source licenses'),
                  subtitle: const Text(
                      'Full license text of every bundled dependency'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppInfo.name,
                    applicationVersion: AppInfo.version,
                    applicationLegalese: AppInfo.legalese,
                  ),
                ),
              ],
            ),
    );
  }

  String _autoAdvanceLabel(int ms) {
    if (ms <= 0) return 'Off (tap Next manually)';
    final s = (ms / 1000).round();
    return '$s seconds';
  }

  Future<void> _showAutoAdvanceDialog(Prefs p) async {
    final current = p.getInt(Prefs.kAutoAdvanceMs, defaultValue: Prefs.kAutoAdvanceDefaultMs);
    final choice = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Auto-advance'),
        children: [
          for (final ms in [0, 3000, 6000, 10000, 15000, 30000])
            RadioListTile<int>(
              title: Text(_autoAdvanceLabel(ms)),
              value: ms,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (choice != null) {
      await p.setInt(Prefs.kAutoAdvanceMs, choice);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      final playerDb = await ref.read(playerDbProvider.future);
      await playerDb.reset();
      ref.invalidate(globalRatingProvider);
      ref.invalidate(journeyProvider);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'monospace',
          color: WR.cyan,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}
