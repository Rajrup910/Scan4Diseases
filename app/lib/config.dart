import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Backend connection settings for the Scan4Disease screening API.
///
/// Resolution order for the base URL (first non-empty wins):
///   1. A runtime override the user typed in the app's "Server settings" dialog. It is
///      persisted, so IP changes never need an app rebuild. This is the durable fix for a
///      laptop whose Wi-Fi (DHCP) address keeps changing.
///   2. A compile-time override: `--dart-define=API_BASE_URL=http://<ip>:8000`.
///   3. A platform default baked into this file (below).
///
/// "localhost" means the DEVICE, not the laptop, so on a physical phone use the laptop's
/// LAN IP (same Wi-Fi, backend on 0.0.0.0) or an `adb reverse tcp:8000 tcp:8000` tunnel.
class ApiConfig {
  ApiConfig._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const _storageKey = 'api_base_url';

  /// Explicit compile-time override.
  static const String _compileOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Runtime override, loaded from storage at startup and updated when the user saves one.
  /// Bumps so widgets listening (the login "Server settings" affordance) can rebuild.
  static final ValueNotifier<String?> runtimeOverride = ValueNotifier<String?>(null);

  /// Platform default when neither override is set.
  ///
  /// Android defaults to 127.0.0.1:8000, which reaches the laptop through
  /// `adb reverse tcp:8000 tcp:8000` over a USB cable. This is deliberately IP-independent:
  /// it keeps working when the laptop's Wi-Fi (DHCP) address changes, and even with Wi-Fi
  /// off. For a pure-Wi-Fi setup (no cable), override this at runtime via the in-app
  /// "Server settings" with the laptop's current LAN IP, e.g. http://192.168.1.7:8000.
  static String get _platformDefault {
    if (kIsWeb) return 'https://scan4diseases.onrender.com';
    if (defaultTargetPlatform == TargetPlatform.android) return 'https://scan4diseases.onrender.com';
    return 'https://scan4diseases.onrender.com';
  }

  /// Read the persisted override once, before the first frame (called from `main`).
  static Future<void> loadPersisted() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      runtimeOverride.value = (saved != null && saved.trim().isNotEmpty) ? saved.trim() : null;
    } catch (_) {
      // Storage unavailable is not fatal; fall back to the compile/platform default.
      runtimeOverride.value = null;
    }
  }

  /// Persist (or clear, when [url] is null/empty) the runtime override.
  static Future<void> setBaseUrl(String? url) async {
    final normalised = (url == null) ? '' : normalise(url);
    if (normalised.isEmpty) {
      await _storage.delete(key: _storageKey);
      runtimeOverride.value = null;
    } else {
      await _storage.write(key: _storageKey, value: normalised);
      runtimeOverride.value = normalised;
    }
  }

  static String get baseUrl {
    final runtime = runtimeOverride.value;
    if (runtime != null && runtime.isNotEmpty) return runtime;
    if (_compileOverride.isNotEmpty) return normalise(_compileOverride);
    return _platformDefault;
  }

  /// Accept forgiving input ("192.168.1.7", "192.168.1.7:8000", "http://host:8000/") and
  /// return a clean origin: add http:// if no scheme, default port 8000 if none, drop any
  /// trailing slash/path.
  static String normalise(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return _stripTrailingSlash(s);
    final port = uri.hasPort ? uri.port : 8000;
    return '${uri.scheme}://${uri.host}:$port';
  }

  static String _stripTrailingSlash(String url) =>
      url.replaceFirst(RegExp(r'/+$'), '');

  /// Turn a relative path from the API (e.g. "/gradcam/xyz.png") into a full URL the Image
  /// widget can fetch.
  static String resolve(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final sep = path.startsWith('/') ? '' : '/';
    return '$baseUrl$sep$path';
  }
}
