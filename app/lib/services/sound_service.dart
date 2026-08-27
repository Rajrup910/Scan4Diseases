import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'haptics_service.dart';

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
    // Treat these as UI sounds, not media: on Android don't request audio focus
    // (so we never duck the user's music and never fight for focus on rapid
    // taps — a common cause of dropped/no playback); on iOS use the ambient
    // category so the cues mix with other audio and honour the silent switch.
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          // `ambient` already mixes with other audio and respects the silent
          // switch; passing mixWithOthers here would trip the plugin's own
          // assert (it's only allowed on playback/playAndRecord/multiRoute).
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
          ),
        ),
      );
    } catch (_) {
      // Non-fatal: default context still plays.
    }
    await _warm();
  }

  Future<void> _warm() async {
    if (_warmed) return;
    _warmed = true;
    // Pre-create one player per cue so the first real play has no allocation
    // latency. We intentionally do NOT use lowLatency/SoundPool here: on Android
    // its load is asynchronous and a `resume()` fired immediately after can play
    // before the clip has loaded — which is exactly the "no sound" symptom. The
    // default media player, driven with stop()+play(AssetSource), plays every
    // time.
    for (final entry in _assets.entries) {
      _playerFor(entry.key);
    }
  }

  AudioPlayer _playerFor(String key) {
    var player = _players[key];
    if (player == null) {
      player = AudioPlayer(playerId: 's4d_$key');
      player.setReleaseMode(ReleaseMode.stop);
      _players[key] = player;
    }
    return player;
  }

  Future<void> _play(String key, {double volume = 0.6}) async {
    if (!enabled.value) return;
    final path = _assets[key];
    if (path == null) return;
    final player = _playerFor(key);
    try {
      // stop() first so a rapid re-trigger restarts cleanly; play() sets the
      // source and starts in one call, so playback never races an async load.
      await player.stop();
      await player.play(AssetSource(path), volume: volume);
    } catch (_) {
      // Best-effort: never let a sound failure surface to the user.
    }
  }

  // --- the cue palette (mirrors the web Sound module) ---------------------
  //
  // Haptics are routed through the independent [Haptics] service (its own
  // on/off preference), so a cue's tactile half still fires when sound is
  // muted — and vice versa.

  /// Soft muted click — the workhorse for buttons, chips, list rows.
  Future<void> tap() {
    Haptics.instance.selection();
    return _play('tap', volume: 0.8);
  }

  /// Two-note affirm for a state flip (theme / sound / a switch).
  Future<void> toggle() {
    Haptics.instance.selection();
    return _play('toggle', volume: 0.9);
  }

  /// A panel / sheet rising into view.
  Future<void> open() => _play('open', volume: 0.85);

  /// A panel / sheet dismissed.
  Future<void> close() => _play('close', volume: 0.8);

  /// Pull-to-refresh / reload whoosh.
  Future<void> refresh() => _play('refresh', volume: 0.85);

  /// Outgoing chat message blip.
  Future<void> send() {
    Haptics.instance.selection();
    return _play('send', volume: 0.85);
  }

  /// Warm major arpeggio — successful login, completed scan, saved action.
  Future<void> success() {
    Haptics.instance.success();
    return _play('success', volume: 1.0);
  }

  /// Gentle two-note descent — failed login, rejected action.
  Future<void> error() {
    Haptics.instance.warning();
    return _play('error', volume: 1.0);
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
