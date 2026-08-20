import 'dart:convert';

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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

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

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await http.post(
      _uri('/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      }),
    );
    await _consumeAuth(res);
  }

  Future<void> login({required String email, required String password}) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    await _consumeAuth(res);
  }

  Future<void> logout() async {
    _token = null;
    user.value = null;
    AppData.clear();
    await _storage.delete(key: _kTokenKey);
  }

  /// Parse a register/login response: store the token, set the user, refresh data.
  Future<void> _consumeAuth(http.Response res) async {
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
    user.value = AuthUser.fromJson(body['user'] as Map<String, dynamic>);
    await AppData.refresh();
  }

  Future<AuthUser> _fetchMe() async {
    final res = await http.get(_uri('/auth/me'), headers: authHeaders);
    if (res.statusCode != 200) {
      throw AuthException('Session expired.');
    }
    return AuthUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  String _messageOf(Map<String, dynamic> body, int status) {
    final msg = body['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    return 'Something went wrong (error $status). Please try again.';
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
