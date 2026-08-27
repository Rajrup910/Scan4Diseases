import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A simple in-app monthly skin self-exam reminder.
///
/// This is deliberately an *in-app* reminder, not an OS push notification: the app ships no
/// notifications plugin, so rather than pretend to schedule a system alert, it persists an
/// opt-in plus a next-due date and surfaces a prompt the next time the app is opened on or
/// after that date. Honest about what it does, and needs zero extra dependencies (it reuses
/// the same secure storage the backend URL uses).
class SelfExamReminder {
  SelfExamReminder._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const _enabledKey = 'self_exam_reminder_enabled';
  static const _dueKey = 'self_exam_next_due';

  /// Roughly one month between reminders.
  static const period = Duration(days: 30);

  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<DateTime?> nextDue = ValueNotifier(null);

  /// Load persisted state once, before the first frame (called from `main`).
  static Future<void> load() async {
    try {
      enabled.value = (await _storage.read(key: _enabledKey)) == 'true';
      final due = await _storage.read(key: _dueKey);
      nextDue.value = due == null ? null : DateTime.tryParse(due);
    } catch (_) {
      enabled.value = false;
      nextDue.value = null;
    }
  }

  static Future<void> enable() async {
    enabled.value = true;
    nextDue.value = DateTime.now().add(period);
    await _write();
  }

  /// Enable the reminder for a specific calendar date the patient picked, rather
  /// than the default one-month cadence. The time is normalised to 09:00 local so
  /// the prompt surfaces in the morning of the chosen day.
  static Future<void> enableOn(DateTime date) async {
    enabled.value = true;
    nextDue.value = DateTime(date.year, date.month, date.day, 9);
    await _write();
  }

  static Future<void> disable() async {
    enabled.value = false;
    nextDue.value = null;
    await _write();
  }

  /// True when a reminder is enabled and its due date has passed.
  static bool get isDue =>
      enabled.value && nextDue.value != null && !DateTime.now().isBefore(nextDue.value!);

  /// Acknowledge a shown reminder by scheduling the next one a period out.
  static Future<void> scheduleNext() async {
    if (!enabled.value) return;
    nextDue.value = DateTime.now().add(period);
    await _write();
  }

  static Future<void> _write() async {
    try {
      await _storage.write(key: _enabledKey, value: enabled.value ? 'true' : 'false');
      if (nextDue.value == null) {
        await _storage.delete(key: _dueKey);
      } else {
        await _storage.write(key: _dueKey, value: nextDue.value!.toIso8601String());
      }
    } catch (_) {
      // Best effort; a lost write just means the reminder state resets to off.
    }
  }
}
