import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tiny file-backed key-value store for user preferences. Avoids the
/// shared_preferences dependency (which pulls in native plugins per
/// platform) for a handful of settings.
///
/// On first read, loads synchronously into memory; on write, persists
/// asynchronously. No versioning; missing keys return defaults.
class Prefs {
  final Map<String, String> _mem = {};
  File? _file;
  bool _loaded = false;

  static Prefs? _instance;
  static Future<Prefs> instance() async {
    final p = _instance ??= Prefs._();
    await p._ensureLoaded();
    return p;
  }

  Prefs._();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'prefs.txt'));
    if (await _file!.exists()) {
      final lines = await _file!.readAsLines();
      for (final line in lines) {
        final eq = line.indexOf('=');
        if (eq > 0) {
          _mem[line.substring(0, eq)] = line.substring(eq + 1);
        }
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (_file == null) return;
    final sb = StringBuffer();
    _mem.forEach((k, v) => sb.writeln('$k=$v'));
    await _file!.writeAsString(sb.toString(), flush: true);
  }

  bool getBool(String key, {required bool defaultValue}) {
    final s = _mem[key];
    if (s == null) return defaultValue;
    return s == '1';
  }

  Future<void> setBool(String key, bool value) async {
    _mem[key] = value ? '1' : '0';
    await _save();
  }

  int getInt(String key, {required int defaultValue}) {
    return int.tryParse(_mem[key] ?? '') ?? defaultValue;
  }

  Future<void> setInt(String key, int value) async {
    _mem[key] = value.toString();
    await _save();
  }

  // Known keys.
  static const kHapticsOn = 'haptics_on';
  static const kSoundOn = 'sound_on';
  /// Auto-advance delay in milliseconds. 0 = never auto-advance.
  static const kAutoAdvanceMs = 'auto_advance_ms';

  /// Single source of truth for the auto-advance default. Must be one of
  /// the options offered by the settings dialog, or the dialog opens with
  /// nothing selected.
  static const kAutoAdvanceDefaultMs = 10000;
  static const kOnboardingSeen = 'onboarding_seen';
}
