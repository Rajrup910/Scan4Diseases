import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../Screens/app_data.dart';

/// The signed-in user, as returned by the backend.
class AuthUser {
  const AuthUser({required this.id, required this.email, this.displayName});
  final int id;
  final String email;
  final String? displayName;

  /// A friendly label for the UI: the display name if set, else the email.
  String get label => (displayName != null && displayName!.isNotEmpty) ? displayName! : email;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        email: '${j['email']}',
        displayName: j['display_name'] as String?,
      );
}

/// Holds the auth token and current user, and talks to the backend's /auth
/// endpoints. A single instance is shared across the app via [AuthService.instance].
///
/// The token is kept in the platform secure store (Keystore on Android), never in
/// plain preferences. On successful auth the user's saved reports are refreshed.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kTokenKey = 'auth_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// Null when signed out. Screens listen to this to gate the UI.
  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  String? _token;
  String? get token => _token;
  bool get isAuthenticated => _token != null && user.value != null;

  /// Authorization header to attach to authenticated requests.
  Map<String, String> get authHeaders =>
      _token == null ? const {} : {'Authorization': 'Bearer $_token'};

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  /// Load a saved session on launch. If the token is missing or rejected, the
  /// user simply stays signed out.
  Future<void> restore() async {
    final saved = await _storage.read(key: _kTokenKey);
    if (saved == null || saved.isEmpty) return;
    _token = saved;
    try {
      user.value = await _fetchMe();
      await AppData.refresh();
    } catch (_) {
      await logout();
    }
  }

  Future<AuthUser> register({
    required String email,
    required String password,
    String? displayName,
    bool deferUserUpdate = false,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    final cleanName = displayName?.trim();

    // The Render free tier can cold-start for ~50s. Warm the server with a
    // cheap GET first (short timeout, best-effort) so the register POST that
    // follows lands on a hot process instead of tripping the app's timeout.
    try {
      await http.get(_uri('/health')).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Warm-up failure is harmless — the actual register call below handles
      // the real error surface.
    }

    Future<http.Response> attempt() => http.post(
          _uri('/auth/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'password': cleanPassword,
            if (cleanName != null && cleanName.isNotEmpty)
              'display_name': cleanName,
          }),
        ).timeout(const Duration(seconds: 75));

    try {
      http.Response res;
      try {
        res = await attempt();
      } on TimeoutException catch (_) {
        // One retry after a cold-start — by now the container is warm.
        res = await attempt();
      }
      return await _consumeAuth(res, deferUserUpdate: deferUserUpdate);
    } on SocketException catch (_) {
      throw AuthException('Cannot reach cloud server. Please check your internet connection.');
    } on TimeoutException catch (_) {
      throw AuthException('The server is still waking up. Please try Create account again — it should go through this time.');
    } on HandshakeException catch (_) {
      throw AuthException('Secure SSL connection failed. Please check your device date/time.');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString().replaceAll('Exception: ', '').trim());
    }
  }

  Future<AuthUser> login({
    required String email,
    required String password,
    bool deferUserUpdate = false,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    try {
      final res = await http.post(
        _uri('/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': cleanEmail, 'password': cleanPassword}),
      ).timeout(const Duration(seconds: 30));
      return await _consumeAuth(res, deferUserUpdate: deferUserUpdate);
    } on SocketException catch (_) {
      throw AuthException('Cannot reach cloud server. Please check your internet connection.');
    } on TimeoutException catch (_) {
      throw AuthException('Server is waking up. Please try again in a few seconds.');
    } on HandshakeException catch (_) {
      throw AuthException('Secure SSL connection failed. Please check your device date/time.');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString().replaceAll('Exception: ', '').trim());
    }
  }

  void activateUser(AuthUser authUser) {
    user.value = authUser;
    AppData.refresh();
  }

  Future<void> logout() async {
    _token = null;
    user.value = null;
    AppData.clear();
    await _storage.delete(key: _kTokenKey);
  }

  /// Parse a register/login response: store the token, set the user, refresh data.
  Future<AuthUser> _consumeAuth(http.Response res, {bool deferUserUpdate = false}) async {
    final Map<String, dynamic> body =
        res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthException(_messageOf(body, res.statusCode));
    }
    final token = body['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw AuthException('The server did not return a valid session.');
    }
    _token = token;
    await _storage.write(key: _kTokenKey, value: token);
    final authUser = AuthUser.fromJson(body['user'] as Map<String, dynamic>);
    if (!deferUserUpdate) {
      user.value = authUser;
      await AppData.refresh();
    }
    return authUser;
  }

  Future<AuthUser> _fetchMe() async {
    final res = await http.get(_uri('/auth/me'), headers: authHeaders).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw AuthException('Session expired.');
    }
    return AuthUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  String _messageOf(Map<String, dynamic> body, int status) {
    final detail = body['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    final msg = body['message'] ?? body['error'];
    if (msg is String && msg.trim().isNotEmpty) return msg.trim();
    if (status == 401) return 'Email or password is incorrect.';
    if (status == 409) return 'An account with this email already exists.';
    if (status == 422) return 'Invalid email or password format.';
    return 'Something went wrong (error $status). Please try again.';
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
