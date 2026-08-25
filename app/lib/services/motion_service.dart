import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide "reduce ambient motion" controller.
///
/// The app has several always-on decorative animations — most notably the
/// [EmeraldWaves] surface, which repaints a full-canvas gradient every frame
/// and is mounted on the home hero, the sign-in button, the slide-to-start
/// track and the floating action button at the same time. That is pleasant on
/// a flagship and costly on a budget device, and it is a lot of persistent
/// movement for users who find motion distracting.
///
/// This flag lets the user freeze that ambient motion without giving up the
/// visual design: surfaces still render their full gradient treatment, they
/// simply hold a still frame instead of animating. Purposeful motion —
/// page transitions, the success tick, list entry — is unaffected, so the app
/// never loses the feedback that tells the user something happened.
///
/// Persisted alongside the theme choice, and restored before the first frame.
class MotionService {
  MotionService._();
  static final MotionService instance = MotionService._();

  static const _storageKey = 'reduce_ambient_motion';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// Whether the user has asked for ambient motion to be held still.
  /// Defaults to false — the full treatment — until [load] restores a choice.
  final ValueNotifier<bool> reduced = ValueNotifier<bool>(false);

  /// Restore the saved preference on launch. A missing value is not an error.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      reduced.value = saved == 'true';
    } catch (_) {
      // Keep the default; secure-storage read failures are non-fatal.
    }
  }

  /// Set the preference and persist it. No-op when unchanged, so listeners are
  /// not notified needlessly.
  Future<void> set(bool value) async {
    if (value == reduced.value) return;
    reduced.value = value;
    try {
      await _storage.write(key: _storageKey, value: value ? 'true' : 'false');
    } catch (_) {
      // In-memory value still updates; persistence is best-effort.
    }
  }

  Future<void> toggle() => set(!reduced.value);

  /// Whether ambient motion should be held still right now — the user's own
  /// preference OR the platform accessibility setting ("Remove animations" on
  /// Android, "Reduce Motion" on iOS). Honouring the OS flag means users who
  /// have already asked the system for less motion get it here without having
  /// to find this switch.
  static bool shouldHold(BuildContext context, bool userPreference) =>
      userPreference || MediaQuery.maybeDisableAnimationsOf(context) == true;
}
