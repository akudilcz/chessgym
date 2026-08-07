import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Which sound to play. Values map to `assets/sfx/<name>.wav`.
enum Sfx { move, capture, check, solve, fail, levelup }

/// Short sound effects for the solve flow.
///
/// Everything here is best-effort: a device that refuses to hand out an
/// audio stream, or a test environment with no audio plugin, must never
/// break a puzzle. The first failure switches the service off rather than
/// retrying on every move.
///
/// One player per effect, each with its source already set, so a move plays
/// instantly instead of decoding on the tap. They are independent, so an
/// effect can overlap the tail of another.
class SfxService {
  SfxService(this._prefs);

  final Prefs _prefs;
  final Map<Sfx, AudioPlayer> _players = {};
  bool _loaded = false;
  bool _broken = false;

  /// Honours the settings toggle. Read on every play so flipping the switch
  /// takes effect immediately.
  bool get enabled =>
      !_broken && _prefs.getBool(Prefs.kSoundOn, defaultValue: true);

  /// Loads every effect. Safe to call more than once.
  Future<void> preload() async {
    if (_loaded || _broken) return;
    try {
      for (final sfx in Sfx.values) {
        final player = AudioPlayer()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource('sfx/${sfx.name}.wav'));
        _players[sfx] = player;
      }
      _loaded = true;
    } catch (e) {
      // No audio on this platform, or the assets are missing. Go quiet.
      debugPrint('[sfx] disabled: $e');
      _broken = true;
      await _disposePlayers();
    }
  }

  /// Fires the effect without waiting for it. Callers are in the middle of
  /// animating a move; they must not be blocked on an audio stream.
  void play(Sfx sfx, {double volume = 1.0}) {
    if (!enabled) return;
    () async {
      try {
        await preload();
        final player = _players[sfx];
        if (player == null) return;
        await player.setVolume(volume);
        // Restart rather than resume: tapping quickly should re-trigger the
        // sound from the top, not continue a tail that is still playing.
        await player.stop();
        await player.resume();
      } catch (e) {
        debugPrint('[sfx] play ${sfx.name} failed: $e');
        _broken = true;
      }
    }();
  }

  Future<void> _disposePlayers() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {
        // A player that never opened is not worth reporting.
      }
    }
    _players.clear();
  }

  void dispose() {
    unawaited(_disposePlayers());
  }
}
