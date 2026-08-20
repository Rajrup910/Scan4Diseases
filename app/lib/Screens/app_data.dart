import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../services/auth_service.dart';

/// One saved screening. Server-persisted fields map to the backend `Report`
/// model; `imagePath` is device-local only (the photo never leaves the phone).
class ScreeningReport {
  final int? id;
  final DateTime date;
  final String condition;
  final String? predictedClass;
  final double? confidence;
  final String triage;
  final String explanation;
  final String? imagePath;
  final Map<String, dynamic> symptoms;

  ScreeningReport({
    this.id,
    required this.date,
    required this.condition,
    this.predictedClass,
    this.confidence,
    required this.triage,
    required this.explanation,
    this.imagePath,
    this.symptoms = const {},
  });

  /// Payload sent to `POST /reports`. Excludes the local image path.
  Map<String, dynamic> toBackendJson() => {
        'condition': condition,
        'predicted_class': predictedClass,
        'confidence': confidence,
        'triage': triage,
        'explanation': explanation,
        'symptoms': symptoms,
      };

  factory ScreeningReport.fromJson(Map<String, dynamic> j, {String? localImagePath}) =>
      ScreeningReport(
        id: j['id'] as int?,
        date: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        condition: '${j['condition'] ?? 'Screening result'}',
        predictedClass: j['predicted_class'] as String?,
        confidence: j['confidence'] is num ? (j['confidence'] as num).toDouble() : null,
        triage: '${j['triage'] ?? ''}',
        explanation: '${j['explanation'] ?? ''}',
        symptoms: j['symptoms'] is Map ? Map<String, dynamic>.from(j['symptoms'] as Map) : const {},
        imagePath: localImagePath,
      );
}

/// The user's reports, synced with the backend. Screens listen to [reports].
class AppData {
  static final ValueNotifier<List<ScreeningReport>> reports = ValueNotifier([]);
  static final ValueNotifier<bool> loading = ValueNotifier(false);

  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  /// Pull the signed-in user's reports from the server. Silently keeps the
  /// current list on failure so a flaky connection never blanks the history.
  static Future<void> refresh() async {
    if (!AuthService.instance.isAuthenticated) return;
    loading.value = true;
    try {
      final res = await http.get(_uri('/reports'), headers: AuthService.instance.authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          reports.value = data
              .whereType<Map<String, dynamic>>()
              .map((e) => ScreeningReport.fromJson(e))
              .toList();
        }
      }
    } catch (_) {
      // Keep whatever we already have.
    } finally {
      loading.value = false;
    }
  }

  /// Save a new screening. Persists to the backend and prepends the stored
  /// version (with its server id). If the save fails, the report is still shown
  /// for this session so the user never loses their result.
  static Future<void> addReport(ScreeningReport report) async {
    try {
      final res = await http.post(
        _uri('/reports'),
        headers: {'Content-Type': 'application/json', ...AuthService.instance.authHeaders},
        body: jsonEncode(report.toBackendJson()),
      );
      if (res.statusCode == 201) {
        final saved = ScreeningReport.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
          localImagePath: report.imagePath,
        );
        reports.value = [saved, ...reports.value];
        return;
      }
    } catch (_) {
      // fall through to the local-only fallback
    }
    reports.value = [report, ...reports.value];
  }

  /// Remove a report. Deletes on the server when it has an id; always updates
  /// the local list so the UI stays responsive.
  static Future<void> deleteReport(ScreeningReport report) async {
    reports.value = reports.value.where((r) => !identical(r, report)).toList();
    if (report.id == null) return;
    try {
      await http.delete(_uri('/reports/${report.id}'), headers: AuthService.instance.authHeaders);
    } catch (_) {
      // Best effort; a later refresh will reconcile.
    }
  }

  /// Clear all in-memory reports (called on logout).
  static void clear() {
    reports.value = [];
  }
}
