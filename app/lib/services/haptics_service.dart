import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide haptic feedback, deliberately decoupled from the sound layer.
///
/// Haptics used to live inside [SoundService] and were gated by the *sound*
/// preference, so muting sound also killed every buzz — which read as "no
/// haptics in the app". This service owns its own on/off preference (default
/// on) so tactile feedback is available even on silent, and so a settings
/// switch can toggle it independently.
///
/// Every call is best-effort and fails soft: a platform without a vibrator, or
/// a haptic effect it doesn't implement, simply produces nothing rather than an
/// error. Feedback is fired at *meaningful* boundaries only (a selection step, a
/// completed action, a warning) — never on every raw pointer event — matching
/// the interaction-design rules in the demo audit.
class Haptics {
  Haptics._();
  static final Haptics instance = Haptics._();

  static const _storageKey = 'haptics_enabled';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// Whether haptics are on. Exposed as a notifier so a settings switch binds
  /// to it. Defaults to on until [load] restores a saved choice.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Restore the saved preference. Safe to call once from `main()`.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved != null) enabled.value = saved == 'true';
    } catch (_) {
      // Non-fatal: keep the default.
    }
  }

  void _fire(Future<void> Function() fn) {
    if (!enabled.value) return;
    try {
      fn();
    } catch (_) {
      // Best-effort: never surface a haptic failure.
    }
  }

  // --- the haptic palette -------------------------------------------------

  /// A crisp tick for a discrete step: a tab change, a stepper, a segment,
  /// moving through a picker/dial notch. The lightest cue.
  void selection() => _fire(HapticFeedback.selectionClick);

  /// A subtle confirm for a light-weight action (a chip, a secondary button).
  void light() => _fire(HapticFeedback.lightImpact);

  /// A firmer bump for a primary action (start a scan, submit, confirm).
  void medium() => _fire(HapticFeedback.mediumImpact);

  /// A strong thud for a major/irreversible moment.
  void heavy() => _fire(HapticFeedback.heavyImpact);

  /// A completion cue — a saved report, a finished scan, a successful login.
  void success() => _fire(HapticFeedback.mediumImpact);

  /// A warning cue for an error or a validation failure.
  void warning() => _fire(HapticFeedback.heavyImpact);

  // --- preference control -------------------------------------------------

  Future<void> setEnabled(bool value) async {
    if (value == enabled.value) return;
    enabled.value = value;
    try {
      await _storage.write(key: _storageKey, value: value ? 'true' : 'false');
    } catch (_) {
      // In-memory value still updates; persistence is best-effort.
    }
    // Confirm tactilely when switching ON (so the user feels it took effect).
    if (value) light();
  }

  Future<void> toggleEnabled() => setEnabled(!enabled.value);
}
