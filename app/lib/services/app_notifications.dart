import 'package:flutter/foundation.dart';

import 'appointments_service.dart';

/// One entry in the in-app notification centre (the bell in the top bar).
///
/// Notifications come from two sources: local events the app raises itself (an
/// appointment request was sent, a self-exam reminder was set) and events
/// derived from the synced appointment list (a doctor approved, declined,
/// cancelled or recommended a visit). Read-state is tracked by [id] so derived
/// items — which are rebuilt on every sync — keep their seen/unseen state.
class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.time,
    this.appointmentId,
    this.read = false,
  });

  /// Stable identity, so a rebuilt derived notification is recognised as the
  /// same one and doesn't reset to unread.
  final String id;

  /// One of: requested | approved | declined | cancelled | recommended |
  /// reminder | info. Drives the icon and accent in the UI.
  final String kind;
  final String title;
  final String body;
  final DateTime time;
  final int? appointmentId;
  bool read;
}

/// App-wide, in-memory notification centre. A singleton [ValueNotifier] the top
/// bar bell listens to for both the badge count and the list contents.
class AppNotifications {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  final ValueNotifier<List<AppNotification>> items = ValueNotifier<List<AppNotification>>([]);
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  final List<AppNotification> _local = [];
  final Set<String> _readIds = <String>{};
  bool _wired = false;

  /// Start deriving notifications from the appointment list. Safe to call more
  /// than once — the listener is only attached on the first call.
  void init() {
    if (_wired) return;
    _wired = true;
    AppointmentsService.instance.items.addListener(_rebuild);
    _rebuild();
  }

  /// Raise a local, app-generated notification (e.g. "request sent").
  void pushLocal({
    required String kind,
    required String title,
    required String body,
    int? appointmentId,
  }) {
    final n = AppNotification(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      title: title,
      body: body,
      time: DateTime.now(),
      appointmentId: appointmentId,
    );
    _local.insert(0, n);
    _rebuild();
  }

  /// Mark everything currently shown as read (called when the bell is opened).
  void markAllRead() {
    for (final n in items.value) {
      n.read = true;
      _readIds.add(n.id);
    }
    unread.value = 0;
    // Re-emit so listeners repaint with the cleared badge.
    items.value = List<AppNotification>.from(items.value);
  }

  void clear() {
    _local.clear();
    _readIds.clear();
    items.value = [];
    unread.value = 0;
  }

  void _rebuild() {
    final derived = <AppNotification>[];
    for (final a in AppointmentsService.instance.items.value) {
      final entry = _fromAppointment(a);
      if (entry != null) derived.add(entry);
    }
    final all = <AppNotification>[..._local, ...derived]
      ..sort((x, y) => y.time.compareTo(x.time));
    // Preserve read-state across rebuilds.
    for (final n in all) {
      if (_readIds.contains(n.id)) n.read = true;
    }
    items.value = all;
    unread.value = all.where((n) => !n.read).length;
  }

  /// Translate a doctor's action on an appointment into a notification. Returns
  /// null for states that don't warrant one (e.g. a patient's own pending
  /// request, which already has its own "request sent" local entry).
  AppNotification? _fromAppointment(Appointment a) {
    final when = '${_fmtDate(a.scheduledFor)} · ${_fmtTime(a.scheduledFor)}';
    switch (a.status) {
      case 'confirmed':
        if (a.recommendedByDoctor) {
          return AppNotification(
            id: 'appt-${a.id}-recommended',
            kind: 'recommended',
            title: 'Your doctor recommended a visit',
            body: 'Reserved for $when. Open Appointments to review it.',
            time: a.scheduledFor,
            appointmentId: a.id,
          );
        }
        return AppNotification(
          id: 'appt-${a.id}-approved',
          kind: 'approved',
          title: 'Appointment approved',
          body: 'Your doctor confirmed your visit on $when.',
          time: a.scheduledFor,
          appointmentId: a.id,
        );
      case 'declined':
        return AppNotification(
          id: 'appt-${a.id}-declined',
          kind: 'declined',
          title: 'Request declined',
          body: a.cancelReason?.isNotEmpty == true
              ? 'Your doctor declined the $when request: ${a.cancelReason}'
              : 'Your doctor declined the request for $when.',
          time: a.scheduledFor,
          appointmentId: a.id,
        );
      case 'cancelled':
        return AppNotification(
          id: 'appt-${a.id}-cancelled',
          kind: 'cancelled',
          title: 'Appointment cancelled',
          body: a.cancelReason?.isNotEmpty == true
              ? 'The $when visit was cancelled: ${a.cancelReason}'
              : 'The $when visit was cancelled.',
          time: a.scheduledFor,
          appointmentId: a.id,
        );
      default:
        return null;
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
