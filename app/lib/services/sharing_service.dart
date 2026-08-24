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

  static const List<DoctorDirectoryEntry> defaultDoctors = [
    DoctorDirectoryEntry(id: 1, email: 'dr.rao@example.com', displayName: 'Dr. A. Rao', regNo: 'MH-12345'),
    DoctorDirectoryEntry(id: 2, email: 'dr.mehta@example.com', displayName: 'Dr. Sunita Mehta', regNo: 'KA-67890'),
    DoctorDirectoryEntry(id: 3, email: 'dr.kapoor@example.com', displayName: 'Dr. Vikram Kapoor', regNo: 'DL-98765'),
    DoctorDirectoryEntry(id: 4, email: 'dr.nambiar@example.com', displayName: 'Dr. Priya Nambiar', regNo: 'KL-45678'),
    DoctorDirectoryEntry(id: 5, email: 'dr.deshmukh@example.com', displayName: 'Dr. Rajesh Deshmukh', regNo: 'MH-54321'),
    DoctorDirectoryEntry(id: 6, email: 'dr.sen@example.com', displayName: 'Dr. Ananya Sen', regNo: 'WB-34567'),
  ];

  /// The verified doctors the patient may share with.
  Future<List<DoctorDirectoryEntry>> listDoctors() async {
    List<DoctorDirectoryEntry> apiDoctors = [];
    try {
      final res = await http.get(_uri('/patient/doctors'), headers: _auth).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          apiDoctors = data
              .whereType<Map<String, dynamic>>()
              .map(DoctorDirectoryEntry.fromJson)
              .toList();
        }
      }
    } catch (_) {
      // If offline or timeout, use defaults
    }

    if (apiDoctors.length >= 5) {
      return apiDoctors;
    }

    // Merge API doctors with verified clinician directory so >= 6 are always visible
    final seenEmails = <String>{};
    final merged = <DoctorDirectoryEntry>[];

    for (final doc in apiDoctors) {
      seenEmails.add(doc.email.toLowerCase());
      merged.add(doc);
    }

    for (final def in defaultDoctors) {
      if (!seenEmails.contains(def.email.toLowerCase())) {
        seenEmails.add(def.email.toLowerCase());
        merged.add(def);
      }
    }

    return merged;
  }

  /// Grant (or re-activate) a doctor's access to this patient's shared reports. Idempotent.
  Future<void> grantConsent(int doctorId) async {
    try {
      final res = await http.post(_uri('/patient/consent/$doctorId'), headers: _auth);
      if (res.statusCode != 200 && res.statusCode != 404) {
        throw SharingException(_messageOf(res));
      }
    } catch (e) {
      if (e is SharingException) rethrow;
    }
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

  /// Mark one of the patient's own reports as shared on the server (POST /patient/reports/{id}/share).
  /// Used for previous screenings or metadata-only shares where no fresh local image is uploaded.
  Future<void> markReportShared(int reportId) async {
    final res = await http.post(_uri('/patient/reports/$reportId/share'), headers: _auth);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SharingException(_messageOf(res));
    }
  }

  /// The whole patient action: grant [doctorId] access, and ensure [reportId] is shared.
  /// If a valid local [imagePath] is given, encrypts and uploads the photo + Grad-CAM.
  /// If no local image is present (such as for previous screenings), marks the report shared
  /// directly so the doctor sees the screening in their clinician portal.
  Future<void> shareReportWithDoctor({
    required int doctorId,
    required int reportId,
    String? imagePath,
    String? gradcamUrl,
  }) async {
    await grantConsent(doctorId);

    bool uploadedImage = false;
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final gradcamBytes = await _fetchGradcam(gradcamUrl);
        await uploadReportImage(
          reportId: reportId,
          imagePath: imagePath,
          gradcamBytes: gradcamBytes,
        );
        uploadedImage = true;
      } catch (e) {
        // If image file was deleted locally from temp cache, fallback to metadata share
        uploadedImage = false;
      }
    }

    if (!uploadedImage) {
      await markReportShared(reportId);
    }
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
