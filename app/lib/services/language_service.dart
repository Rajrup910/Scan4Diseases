import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide response language for the AI explanation.
///
/// This controls the `language` field sent to the backend `POST /predict`, which
/// the language model (gemma2) uses to write its answer — the same model handles
/// both English and Hindi. It governs the *generated explanation*, not the static
/// UI labels; full interface localization is a separate, larger piece of work.
///
/// The choice is persisted (Keystore on Android, same store as the auth token) so
/// it survives app restarts. A single instance is shared via [LanguageService.instance];
/// screens listen to [code] to react to changes.
class LanguageService {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  static const _storageKey = 'response_language';

  /// Backend language code -> human label shown in the picker. The codes must match
  /// the backend `Language` enum values ("en", "hi").
  static const Map<String, String> supported = {'en': 'English', 'hi': 'हिन्दी'};
  static const String _fallback = 'en';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// The active language code. Defaults to English until [load] restores a saved choice.
  final ValueNotifier<String> code = ValueNotifier<String>(_fallback);

  /// Human-readable label for the active language, for display in settings.
  String get label => supported[code.value] ?? supported[_fallback]!;

  /// Restore the saved language on launch. Falls back to English if nothing is
  /// stored or the stored value is no longer supported.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved != null && supported.containsKey(saved)) {
        code.value = saved;
      }
    } catch (_) {
      // Keep the default; a missing preference is not an error.
    }
  }

  /// Change the active language and persist it. No-op for an unknown code or the
  /// value already selected, so listeners are not notified needlessly.
  Future<void> set(String value) async {
    if (!supported.containsKey(value) || value == code.value) return;
    code.value = value;
    try {
      await _storage.write(key: _storageKey, value: value);
    } catch (_) {
      // The in-memory value still updates; persistence is best-effort.
    }
  }
}
