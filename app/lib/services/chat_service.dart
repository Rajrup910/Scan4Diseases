import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service.dart';

/// One assistant reply from `POST /chat`.
class ChatResult {
  ChatResult({
    required this.text,
    required this.available,
    this.disclaimer = '',
    this.filtered = false,
  });

  final String text;
  final bool available; // false = LLM offline / unreachable; `text` is a user-safe notice.
  final String disclaimer;
  final bool filtered; // the backend safety filter altered the reply.
}

/// Client for the backend's diagnosis-aware conversation endpoint.
///
/// The backend is stateless: it keeps nothing between turns, so the client echoes the
/// prediction context and prior turns on every request. No RAG — the result being discussed
/// is small enough to pass inline, and the model's own knowledge covers the rest.
class ChatService {
  static Future<ChatResult> send({
    required String message,
    required List<Map<String, String>> history,
    Map<String, dynamic>? prediction,
    Map<String, dynamic>? questionnaire,
    String language = 'en',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat');
    final payload = <String, dynamic>{
      'message': message,
      'language': language,
      'history': history,
      if (prediction != null) 'prediction': prediction,
      if (questionnaire != null && questionnaire.isNotEmpty) 'questionnaire': questionnaire,
    };
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...AuthService.instance.authHeaders,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      if (res.statusCode == 503) {
        return ChatResult(
          text: _message(res.body) ??
              'The assistant is offline right now. Your result and its guidance are unaffected.',
          available: false,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return ChatResult(
          text: _message(res.body) ?? 'Something went wrong (${res.statusCode}).',
          available: false,
        );
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        return ChatResult(text: 'The assistant returned an unexpected response.', available: false);
      }
      return ChatResult(
        text: body['response']?.toString() ?? '',
        available: true,
        disclaimer: body['disclaimer']?.toString() ?? '',
        filtered: body['filtered'] == true,
      );
    } catch (_) {
      return ChatResult(
        text: 'Could not reach the assistant. Check the connection and try again.',
        available: false,
      );
    }
  }

  static String? _message(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['message'] is String) return d['message'] as String;
    } catch (_) {/* not JSON */}
    return null;
  }
}
