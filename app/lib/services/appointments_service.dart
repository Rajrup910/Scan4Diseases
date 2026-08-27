import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service.dart';

/// One booked (or requested / cancelled) visit between the patient and a doctor, as returned
/// by the backend `/appointments` API. Times arrive as UTC ISO strings and are kept local.
class Appointment {
  Appointment({
    required this.id,
    required this.doctorId,
    required this.patientId,
    this.reportId,
    required this.scheduledFor,
    required this.durationMinutes,
    required this.reason,
    required this.status,
    required this.createdBy,
    this.cancelledBy,
    this.cancelReason,
    this.unreadForPatient = false,
    this.doctorName,
    this.reportCondition,
  });

  final int id;
  final int doctorId;
  final int patientId;
  final int? reportId;
  final DateTime scheduledFor;
  final int durationMinutes;
  final String reason;
  final String status; // requested | confirmed | declined | cancelled | completed
  final String createdBy; // patient | doctor
  final String? cancelledBy;
  final String? cancelReason;
  final bool unreadForPatient;
  final String? doctorName;
  final String? reportCondition;

  bool get isRequested => status == 'requested';
  bool get isConfirmed => status == 'confirmed';
  bool get isDeclined => status == 'declined';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isLive => isRequested || isConfirmed;
  bool get recommendedByDoctor => createdBy == 'doctor';
  bool get isPast => scheduledFor.isBefore(DateTime.now());

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] as int,
        doctorId: j['doctor_id'] as int,
        patientId: j['patient_id'] as int,
        reportId: j['report_id'] as int?,
        scheduledFor:
            DateTime.tryParse('${j['scheduled_for']}')?.toLocal() ?? DateTime.now(),
        durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 30,
        reason: '${j['reason'] ?? ''}',
        status: '${j['status'] ?? 'requested'}',
        createdBy: '${j['created_by'] ?? 'patient'}',
        cancelledBy: j['cancelled_by'] as String?,
        cancelReason: j['cancel_reason'] as String?,
        unreadForPatient: j['unread_for_patient'] == true,
        doctorName: j['doctor_name'] as String?,
        reportCondition: j['report_condition'] as String?,
      );
}

/// Patient-side appointment booking, synced with the backend. Screens listen to [items] and
/// the [unread] badge count; both refresh together. Mirrors the shape of [AppData].
class AppointmentsService {
  AppointmentsService._();
  static final AppointmentsService instance = AppointmentsService._();

  final ValueNotifier<List<Appointment>> items = ValueNotifier<List<Appointment>>([]);
  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
  Map<String, String> get _auth => AuthService.instance.authHeaders;

  /// Pull the signed-in patient's appointments. Silently keeps the current list on failure.
  Future<void> refresh() async {
    if (!AuthService.instance.isAuthenticated) return;
    loading.value = true;
    try {
      final res = await http
          .get(_uri('/appointments'), headers: _auth)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          final list = data
              .whereType<Map<String, dynamic>>()
              .map(Appointment.fromJson)
              .toList();
          items.value = list;
          unread.value = list.where((a) => a.unreadForPatient).length;
        }
      }
    } catch (_) {
      // Keep whatever we already have.
    } finally {
      loading.value = false;
    }
  }

  /// Lightweight badge refresh for the Services tab, without pulling the whole list.
  Future<void> refreshUnread() async {
    if (!AuthService.instance.isAuthenticated) return;
    try {
      final res = await http
          .get(_uri('/appointments/unread-count'), headers: _auth)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['count'] is num) {
          unread.value = (data['count'] as num).toInt();
        }
      }
    } catch (_) {/* best-effort */}
  }

  /// Clear the "your doctor responded" badge once the patient has opened the list.
  Future<void> markSeen() async {
    if (unread.value == 0) return;
    unread.value = 0;
    try {
      await http
          .post(_uri('/appointments/mark-seen'), headers: _auth)
          .timeout(const Duration(seconds: 12));
    } catch (_) {/* best-effort; a later refresh reconciles */}
  }

  /// Book a visit. Returns the created appointment (status `requested`).
  Future<Appointment> book({
    required int doctorId,
    int? reportId,
    required DateTime scheduledFor,
    int durationMinutes = 30,
    String reason = '',
  }) async {
    try {
      final res = await http
          .post(
            _uri('/appointments'),
            headers: {'Content-Type': 'application/json', ..._auth},
            body: jsonEncode({
              'doctor_id': doctorId,
              if (reportId != null) 'report_id': reportId,
              // Send UTC ISO so the server stores an aware time.
              'scheduled_for': scheduledFor.toUtc().toIso8601String(),
              'duration_minutes': durationMinutes,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 201) {
        final appt = Appointment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        items.value = [appt, ...items.value];
        return appt;
      }
      throw AppointmentException(_messageOf(res));
    } on AppointmentException {
      rethrow;
    } catch (e) {
      throw AppointmentException(
          'Could not book the appointment. Please check your connection and try again.');
    }
  }

  /// Cancel (or decline a doctor-recommended) appointment.
  Future<void> cancel(int id, {String reason = ''}) async {
    try {
      final res = await http
          .post(
            _uri('/appointments/$id/cancel'),
            headers: {'Content-Type': 'application/json', ..._auth},
            body: jsonEncode({'reason': reason}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final updated = Appointment.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        items.value = [
          for (final a in items.value) if (a.id == id) updated else a,
        ];
        return;
      }
      throw AppointmentException(_messageOf(res));
    } on AppointmentException {
      rethrow;
    } catch (e) {
      throw AppointmentException('Could not cancel the appointment. Please try again.');
    }
  }

  void clear() {
    items.value = [];
    unread.value = 0;
  }

  String _messageOf(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map) {
        for (final k in ['detail', 'message', 'error']) {
          final v = body[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
    } catch (_) {}
    return 'Something went wrong (error ${res.statusCode}). Please try again.';
  }
}

class AppointmentException implements Exception {
  AppointmentException(this.message);
  final String message;
  @override
  String toString() => message;
}
