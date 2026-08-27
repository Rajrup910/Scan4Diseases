import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide subtle UI sound theme.
///
/// A small set of short, low-volume cues — synthesised WAVs bundled under
/// `assets/sounds/` — that give the app the same tactile feel as the clinician
/// web portal (whose Web-Audio engine uses the identical palette: a soft muted
/// tap, a rising "open", a warm success arpeggio, a gentle two-note error, and
/// so on). Cues are paired with light haptics on the most important moments so
/// the feedback lands even in a noisy room or on silent.
///
/// Everything is best-effort and fails soft: a missing asset, an audio-focus
/// hiccup, or a platform without the plugin simply produces no sound rather
/// than an error. The user can mute the whole layer; the choice persists
/// alongside the theme/motion preferences and is restored before the first
/// frame.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const _storageKey = 'sound_effects_enabled';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// Whether interaction sounds are on. Defaults to on until [load] restores a
  /// saved choice. Exposed as a notifier so a settings switch can bind to it.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// One preloaded player per cue, so a tap during a success chime doesn't cut
  /// the chime off, and each cue re-triggers with near-zero latency.
  final Map<String, AudioPlayer> _players = {};
  bool _warmed = false;

  static const Map<String, String> _assets = {
    'tap': 'sounds/tap.wav',
    'toggle': 'sounds/toggle.wav',
    'open': 'sounds/open.wav',
    'close': 'sounds/close.wav',
    'refresh': 'sounds/refresh.wav',
    'send': 'sounds/send.wav',
    'success': 'sounds/success.wav',
    'error': 'sounds/error.wav',
  };

  /// Restore the saved preference and pre-warm the players. Safe to call once
  /// from `main()` before the first frame; a read failure keeps the default.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved != null) enabled.value = saved == 'true';
    } catch (_) {
      // Non-fatal: keep the default.
    }
    await _warm();
  }

  Future<void> _warm() async {
    if (_warmed) return;
    _warmed = true;
    for (final entry in _assets.entries) {
      try {
        final player = AudioPlayer(playerId: 's4d_${entry.key}');
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(entry.value));
        _players[entry.key] = player;
      } catch (_) {
        // Skip any cue that fails to load; the rest still work.
      }
    }
  }

  Future<void> _play(String key, {double volume = 0.6}) async {
    if (!enabled.value) return;
    await _warm();
    final player = _players[key];
    if (player == null) return;
    try {
      await player.setVolume(volume);
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      // Best-effort: never let a sound failure surface to the user.
    }
  }

  void _haptic(Future<void> Function() fn) {
    if (!enabled.value) return;
    try {
      fn();
    } catch (_) {}
  }

  // --- the cue palette (mirrors the web Sound module) ---------------------

  /// Soft muted click — the workhorse for buttons, chips, list rows.
  Future<void> tap() {
    _haptic(HapticFeedback.selectionClick);
    return _play('tap', volume: 0.5);
  }

  /// Two-note affirm for a state flip (theme / sound / a switch).
  Future<void> toggle() {
    _haptic(HapticFeedback.selectionClick);
    return _play('toggle', volume: 0.6);
  }

  /// A panel / sheet rising into view.
  Future<void> open() => _play('open', volume: 0.55);

  /// A panel / sheet dismissed.
  Future<void> close() => _play('close', volume: 0.5);

  /// Pull-to-refresh / reload whoosh.
  Future<void> refresh() => _play('refresh', volume: 0.55);

  /// Outgoing chat message blip.
  Future<void> send() {
    _haptic(HapticFeedback.selectionClick);
    return _play('send', volume: 0.55);
  }

  /// Warm major arpeggio — successful login, completed scan, saved action.
  Future<void> success() {
    _haptic(HapticFeedback.lightImpact);
    return _play('success', volume: 0.75);
  }

  /// Gentle two-note descent — failed login, rejected action.
  Future<void> error() {
    _haptic(HapticFeedback.heavyImpact);
    return _play('error', volume: 0.75);
  }

  // --- preference control -------------------------------------------------

  Future<void> setEnabled(bool value) async {
    if (value == enabled.value) return;
    enabled.value = value;
    try {
      await _storage.write(key: _storageKey, value: value ? 'true' : 'false');
    } catch (_) {
      // In-memory value still updates; persistence is best-effort.
    }
    // Confirm audibly when switching ON (silence would be ambiguous).
    if (value) toggle();
  }

  Future<void> toggleEnabled() => setEnabled(!enabled.value);

  /// Release the players. Rarely needed (the service lives for the app's
  /// lifetime) but provided for completeness.
  Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _players.clear();
    _warmed = false;
  }
}
