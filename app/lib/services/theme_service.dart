import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide light / dark appearance controller.
///
/// Persists the user's choice (Keystore on Android, the same secure store used
/// for the auth token and language) so the app re-opens in the last-used mode,
/// and exposes a single shared instance whose [mode] notifier the root
/// [MaterialApp] listens to. Three states are supported:
///
///   * [ThemeMode.system] – follow the OS light/dark setting (default)
///   * [ThemeMode.light]  – always the clinical light theme
///   * [ThemeMode.dark]   – always the glossy emerald dark theme
///
/// The Profile screen toggles between light and dark; "system" is the initial
/// value on a fresh install so first-run respects the phone's setting.
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _storageKey = 'theme_mode';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// The active theme mode. Defaults to [ThemeMode.system] until [load] restores
  /// a saved choice.
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Convenience: whether the effective appearance is dark, resolving
  /// [ThemeMode.system] against the current platform brightness.
  bool isDark(BuildContext context) {
    switch (mode.value) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _serialize(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Restore the saved appearance on launch. Falls back to [ThemeMode.system]
  /// if nothing is stored — a missing preference is not an error.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      mode.value = _parse(saved);
    } catch (_) {
      // Keep the default; secure-storage read failures are non-fatal.
    }
  }

  /// Set the active mode and persist it. No-op when unchanged, so listeners are
  /// not notified needlessly.
  Future<void> set(ThemeMode value) async {
    if (value == mode.value) return;
    mode.value = value;
    try {
      await _storage.write(key: _storageKey, value: _serialize(value));
    } catch (_) {
      // In-memory value still updates; persistence is best-effort.
    }
  }

  /// Flip between explicit light and dark. Given the current effective
  /// brightness, choosing the opposite always lands the user where the toggle
  /// implies, even when starting from [ThemeMode.system].
  Future<void> toggle(BuildContext context) =>
      set(isDark(context) ? ThemeMode.light : ThemeMode.dark);
}
