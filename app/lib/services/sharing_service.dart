import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service.dart';

/// A verified doctor the patient can share a report with, from `GET /patient/doctors`.
class DoctorDirectoryEntry {
  const DoctorDirectoryEntry({
    required this.id,
    required this.email,
    this.displayName,
    this.regNo,
  });

  final int id;
  final String email;
  final String? displayName;
  final String? regNo;

  /// What to show in the picker: the display name if the doctor has one, else the email.
  String get label =>
      (displayName != null && displayName!.isNotEmpty) ? displayName! : email;

  factory DoctorDirectoryEntry.fromJson(Map<String, dynamic> j) => DoctorDirectoryEntry(
        id: j['id'] as int,
        email: '${j['email']}',
        displayName: j['display_name'] as String?,
        regNo: j['medical_reg_no'] as String?,
      );
}

/// Patient-side sharing: list the available doctors, then grant a chosen one access and
/// upload the report's lesion image so it appears in that doctor's web portal.
///
/// The photo is only ever sent from here, on the patient's explicit action — never during
/// screening (`/predict` keeps the image in memory only). Uploading also marks the report
/// shared on the server, so a single confirmation does the whole "share with my doctor" step.
class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
  Map<String, String> get _auth => AuthService.instance.authHeaders;

  /// The verified doctors the patient may share with.
  Future<List<DoctorDirectoryEntry>> listDoctors() async {
    final res = await http.get(_uri('/patient/doctors'), headers: _auth);
    if (res.statusCode != 200) throw SharingException(_messageOf(res));
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(DoctorDirectoryEntry.fromJson)
        .toList();
  }

  /// Grant (or re-activate) a doctor's access to this patient's shared reports. Idempotent.
  Future<void> grantConsent(int doctorId) async {
    final res = await http.post(_uri('/patient/consent/$doctorId'), headers: _auth);
    if (res.statusCode != 200) throw SharingException(_messageOf(res));
  }

  /// Upload the lesion image (and optional Grad-CAM overlay) for one of the patient's own
  /// reports. The server encrypts it at rest and marks the report shared. The declared
  /// content type is irrelevant — the backend validates by decoding the bytes — so, like the
  /// `/predict` upload, we send the raw file without a MediaType.
  Future<void> uploadReportImage({
    required int reportId,
    required String imagePath,
    String? gradcamPath,
    Uint8List? gradcamBytes,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/patient/reports/$reportId/image'))
      ..headers.addAll(_auth)
      ..files.add(await http.MultipartFile.fromPath('image', imagePath));
    if (gradcamBytes != null && gradcamBytes.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes('gradcam', gradcamBytes, filename: 'gradcam.png'));
    } else if (gradcamPath != null && gradcamPath.isNotEmpty) {
      req.files.add(await http.MultipartFile.fromPath('gradcam', gradcamPath));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SharingException(_messageOf(res));
    }
  }

  /// Best-effort: download the temporary Grad-CAM overlay the backend produced for this
  /// screening, so it can be shared alongside the lesion photo. Returns null if it can't be
  /// fetched (it expires ~15 min after the scan) — sharing then proceeds with the photo only.
  Future<Uint8List?> _fetchGradcam(String? gradcamUrl) async {
    if (gradcamUrl == null || gradcamUrl.isEmpty) return null;
    try {
      final fullUrl = ApiConfig.resolve(gradcamUrl);
      final res = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
    } catch (_) {/* overlay is optional; never block the share on it */}
    return null;
  }

  /// The whole patient action: give [doctorId] access, then upload [imagePath] for
  /// [reportId] (which also shares it). If [gradcamUrl] is given, the overlay is fetched and
  /// uploaded too. After this, the doctor sees the report — and its heatmap — in the portal.
  Future<void> shareReportWithDoctor({
    required int doctorId,
    required int reportId,
    required String imagePath,
    String? gradcamUrl,
  }) async {
    await grantConsent(doctorId);
    final gradcamBytes = await _fetchGradcam(gradcamUrl);
    await uploadReportImage(
      reportId: reportId,
      imagePath: imagePath,
      gradcamBytes: gradcamBytes,
    );
  }

  String _messageOf(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String && (body['message'] as String).isNotEmpty) {
        return body['message'] as String;
      }
    } catch (_) {/* fall through to the generic message */}
    return 'Sharing failed (error ${res.statusCode}). Please try again.';
  }
}

class SharingException implements Exception {
  SharingException(this.message);
  final String message;
  @override
  String toString() => message;
}
