import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config.dart';

/// Client for the Scan4Disease FastAPI backend (`POST /predict`).
///
/// The backend is the source of truth for the request/response contract. Two
/// things matter here and are easy to get wrong:
///
///   1. The questionnaire is validated with `extra="forbid"` and typed enums.
///      Sending an unknown key, a wrong enum value, or the wrong type returns
///      HTTP 422. So we only forward answered fields, and `SymptomsList` is
///      responsible for emitting backend-valid values.
///
///   2. `gradcam_url` comes back as a relative path ("/gradcam/xyz.png"). The UI
///      needs an absolute URL to display it, so we resolve it here and stash it
///      under `gradcam_display_url`.
class DiagnosisApi {
  DiagnosisApi({String? baseUrl})
      : baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/+$'), '');

  final String baseUrl;

  Future<Map<String, dynamic>> predict({
    required XFile image,
    required Map<String, dynamic> questionnaire,
    String language = 'en',
  }) async {
    final Uri uri = Uri.parse('$baseUrl/predict');
    final Uint8List bytes = await image.readAsBytes();

    // Drop unanswered (null) fields. The backend treats a missing field as
    // "not reported"; sending an explicit null for an enum can still trip
    // validation, so it is cleaner to omit them entirely.
    final cleaned = <String, dynamic>{
      for (final e in questionnaire.entries)
        if (e.value != null) e.key: e.value,
    };

    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: image.name.isEmpty ? 'skin_image.jpg' : image.name,
      ))
      ..fields['questionnaire'] = jsonEncode(cleaned)
      ..fields['language'] = language;

    final response = await request.send().timeout(const Duration(seconds: 90));
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_friendlyError(response.statusCode, body), response.statusCode);
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('The screening service returned an unexpected response.', response.statusCode);
    }

    // Resolve the Grad-CAM path to something Image.network can load.
    final gradcam = decoded['gradcam_url'];
    if (gradcam is String && gradcam.isNotEmpty) {
      decoded['gradcam_display_url'] = ApiConfig.resolve(gradcam);
    }
    return decoded;
  }

  /// Turn the backend's structured error into a message safe to show a user.
  String _friendlyError(int status, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {/* fall through */}
    if (status == 503) return 'The screening model is not available right now. Please try again shortly.';
    if (status == 422) return 'The image or answers could not be processed. Please try a clearer photo.';
    return 'The screening service returned an error ($status).';
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}
