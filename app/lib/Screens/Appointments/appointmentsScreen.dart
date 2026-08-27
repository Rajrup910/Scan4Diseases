import 'package:flutter/material.dart';

import '../../services/appointments_service.dart';
import '../../services/sharing_service.dart';
import '../../services/sound_service.dart';
import '../../services/haptics_service.dart';
import '../../services/theme_service.dart';
import '../app_data.dart';
import '../theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _fmtDate(DateTime d) => '${_wdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Colour + label + icon for an appointment status, theme-aware.
class _StatusStyle {
  const _StatusStyle(this.label, this.color, this.tint, this.icon);
  final String label;
  final Color color;
  final Color tint;
  final IconData icon;

  static _StatusStyle of(Appointment a, bool dark) {
    switch (a.status) {
      case 'confirmed':
        final c = dark ? Themes.tealLight : Themes.routine;
        return _StatusStyle('Confirmed', c, c.withValues(alpha: dark ? 0.16 : 0.12),
            Icons.event_available_rounded);
      case 'declined':
        return _StatusStyle('Declined', Themes.danger, Themes.danger.withValues(alpha: 0.12),
            Icons.event_busy_rounded);
      case 'cancelled':
        final c = dark ? Themes.darkInkSoft : Themes.inkMuted;
        return _StatusStyle('Cancelled', c, c.withValues(alpha: 0.14),
            Icons.event_busy_rounded);
      case 'completed':
        return _StatusStyle('Completed', const Color(0xFF1A56B8),
            const Color(0xFF1A56B8).withValues(alpha: 0.12), Icons.check_circle_rounded);
      case 'requested':
      default:
        return _StatusStyle('Awaiting approval', Themes.soon,
            Themes.soon.withValues(alpha: 0.14), Icons.hourglass_top_rounded);
    }
  }
}

/// The patient's appointments hub: a list of booked visits (upcoming + closed) with a
/// prominent "Book an appointment" action. Doctor responses (approve / decline / cancel /
/// recommend) surface here with a status badge and, where relevant, the doctor's note.
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  @override
  void initState() {
    super.initState();
    // Pull fresh data, then clear the "responded" badge once the patient is looking.
    AppointmentsService.instance.refresh().then((_) {
      AppointmentsService.instance.markSeen();
    });
  }

  Future<void> _openBooking({Appointment? rebook}) async {
    SoundService.instance.open();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingSheet(rebook: rebook),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.mode,
      builder: (_, __, ___) {
        final dark = ThemeService.instance.isDark(context);
        final ink = dark ? Themes.darkInk : Themes.ink;
        final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
        return Scaffold(
          backgroundColor: dark ? Themes.darkCanvas : Themes.canvas,
          appBar: AppBar(
            title: const Text('Appointments'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  SoundService.instance.refresh();
                  AppointmentsService.instance.refresh();
                },
              ),
            ],
          ),
          body: ValueListenableBuilder<List<Appointment>>(
            valueListenable: AppointmentsService.instance.items,
            builder: (context, list, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: AppointmentsService.instance.loading,
                builder: (context, loading, __) {
                  final upcoming = list
                      .where((a) => a.isLive && !a.isPast)
                      .toList()
                    ..sort((x, y) => x.scheduledFor.compareTo(y.scheduledFor));
                  final closed = list
                      .where((a) => !(a.isLive && !a.isPast))
                      .toList()
                    ..sort((x, y) => y.scheduledFor.compareTo(x.scheduledFor));

                  return RefreshIndicator(
                    onRefresh: () => AppointmentsService.instance.refresh(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                      children: [
                        Text(
                          'Book a consultation with a verified dermatologist, or review a visit '
                          'your doctor recommended. You approve every booking; your doctor '
                          'approves every request.',
                          style: TextStyle(color: inkSoft, height: 1.4, fontSize: 13.5),
                        ),
                        const SizedBox(height: 14),
                        _BookButton(onTap: () => _openBooking()),
                        const SizedBox(height: 20),
                        if (loading && list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (list.isEmpty)
                          _EmptyState(dark: dark)
                        else ...[
                          if (upcoming.isNotEmpty) ...[
                            _groupHeader('Upcoming', upcoming.length, ink),
                            const SizedBox(height: 10),
                            for (var i = 0; i < upcoming.length; i++)
                              _AppointmentCard(
                                appt: upcoming[i],
                                dark: dark,
                                index: i,
                                onCancel: () => _confirmCancel(upcoming[i], dark),
                              ),
                          ],
                          if (closed.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _groupHeader('Past & closed', closed.length, ink),
                            const SizedBox(height: 10),
                            for (var i = 0; i < closed.length; i++)
                              _AppointmentCard(
                                appt: closed[i],
                                dark: dark,
                                index: i,
                                onRebook: (closed[i].isCancelled || closed[i].isDeclined)
                                    ? () => _openBooking(rebook: closed[i])
                                    : null,
                              ),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _groupHeader(String label, int count, Color ink) => Row(
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Themes.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12, color: Themes.brand)),
          ),
        ],
      );

  Future<void> _confirmCancel(Appointment a, bool dark) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? Themes.darkSurface : Colors.white,
        title: const Text('Cancel this appointment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your doctor will be notified. You can rebook any time.',
              style: TextStyle(
                  color: dark ? Themes.darkInkSoft : Themes.inkSoft, height: 1.35, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Reason (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Themes.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel visit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppointmentsService.instance.cancel(a.id, reason: controller.text.trim());
      SoundService.instance.success();
      Haptics.instance.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Appointment cancelled. Your doctor has been notified.'),
      ));
    } catch (e) {
      SoundService.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Themes.danger,
        content: Text(e is AppointmentException ? e.message : 'Could not cancel. Please try again.'),
      ));
    }
  }
}

class _BookButton extends StatelessWidget {
  const _BookButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Book an appointment',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: dark
          ? Themes.liquidGlassDecoration(radius: 20, dark: true)
          : Themes.liquidGlassDecoration(radius: 20),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Themes.brand.withValues(alpha: dark ? 0.18 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.calendar_month_rounded,
                color: dark ? Themes.tealLight : Themes.brand, size: 32),
          ),
          const SizedBox(height: 16),
          Text('No appointments yet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: ink)),
          const SizedBox(height: 6),
          Text(
            'Tap “Book an appointment” above to request a consultation with a verified '
            'dermatologist. Your doctor will confirm the slot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: inkSoft, height: 1.4, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

/// One appointment card, with a subtle staggered entrance so the list assembles smoothly.
class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appt,
    required this.dark,
    required this.index,
    this.onCancel,
    this.onRebook,
  });
  final Appointment appt;
  final bool dark;
  final int index;
  final VoidCallback? onCancel;
  final VoidCallback? onRebook;

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 60 * (widget.index.clamp(0, 6))), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appt;
    final dark = widget.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final st = _StatusStyle.of(a, dark);
    final closedLook = a.isCancelled || a.isDeclined;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: dark
              ? Themes.liquidGlassDecoration(radius: 18, dark: true)
              : Themes.liquidGlassDecoration(radius: 18),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date block.
                    Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: st.tint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: st.color.withValues(alpha: 0.30)),
                      ),
                      child: Column(
                        children: [
                          Text('${a.scheduledFor.day}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 20, color: st.color)),
                          Text(_months[a.scheduledFor.month - 1],
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 11.5, color: st.color)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.doctorName ?? 'Your doctor',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: ink,
                                decoration: closedLook ? TextDecoration.lineThrough : null),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 13.5, color: inkSoft),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${_fmtDate(a.scheduledFor)} · ${_fmtTime(a.scheduledFor)} · ${a.durationMinutes} min',
                                  style: TextStyle(color: inkSoft, fontSize: 12.3),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(style: st),
                  ],
                ),
                if (a.recommendedByDoctor && a.isConfirmed) ...[
                  const SizedBox(height: 10),
                  _ribbon(
                    Icons.stars_rounded,
                    'Recommended by your doctor',
                    dark ? Themes.tealLight : Themes.brand,
                    (dark ? Themes.tealLight : Themes.brand).withValues(alpha: dark ? 0.14 : 0.09),
                  ),
                ],
                if ((a.reason).isNotEmpty || a.reportCondition != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: dark ? Themes.darkSurfaceDim : Themes.surfaceDim,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.reportCondition != null) ...[
                          Row(children: [
                            Icon(Icons.description_outlined, size: 14, color: inkSoft),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('About your ${a.reportCondition} screening',
                                  style: TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
                            ),
                          ]),
                          if ((a.reason).isNotEmpty) const SizedBox(height: 6),
                        ],
                        if ((a.reason).isNotEmpty)
                          Text(a.reason,
                              style: TextStyle(fontSize: 12.8, height: 1.35, color: inkSoft)),
                      ],
                    ),
                  ),
                ],
                if (closedLook && (a.cancelReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ribbon(
                    Icons.info_outline_rounded,
                    '${a.isDeclined ? 'Declined' : 'Cancelled'}: ${a.cancelReason}',
                    Themes.danger,
                    Themes.danger.withValues(alpha: 0.09),
                  ),
                ],
                if (widget.onCancel != null || widget.onRebook != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.onRebook != null)
                        TextButton.icon(
                          onPressed: () {
                            SoundService.instance.tap();
                            widget.onRebook!();
                          },
                          icon: const Icon(Icons.event_repeat_rounded, size: 18),
                          label: const Text('Rebook'),
                        ),
                      if (widget.onCancel != null)
                        TextButton.icon(
                          onPressed: () {
                            Haptics.instance.warning();
                            widget.onCancel!();
                          },
                          style: TextButton.styleFrom(foregroundColor: Themes.danger),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Cancel'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ribbon(IconData icon, String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12.3, height: 1.3, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.style});
  final _StatusStyle style;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: style.tint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: style.color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 13, color: style.color),
            const SizedBox(width: 4),
            Text(style.label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: style.color)),
          ],
        ),
      );
}

/// The booking bottom sheet: choose a doctor, a slot, an optional case to discuss, and a
/// reason. On confirm it books the request and shows a success animation.
class _BookingSheet extends StatefulWidget {
  const _BookingSheet({this.rebook});

  /// When set, pre-fills the doctor and linked case from a cancelled/declined visit.
  final Appointment? rebook;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late Future<List<DoctorDirectoryEntry>> _doctors;
  int? _doctorId;
  DateTime? _date;
  TimeOfDay? _time;
  int _duration = 30;
  int? _reportId;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _doctors = SharingService.instance.listDoctors();
    if (widget.rebook != null) {
      _doctorId = widget.rebook!.doctorId;
      _reportId = widget.rebook!.reportId;
      if (widget.rebook!.reason.isNotEmpty) _reasonCtrl.text = widget.rebook!.reason;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  DateTime? get _combined {
    if (_date == null || _time == null) return null;
    return DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
  }

  bool get _valid => _doctorId != null && _combined != null && _combined!.isAfter(DateTime.now());

  Future<void> _pickDate(bool dark) async {
    SoundService.instance.tap();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    SoundService.instance.tap();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit(List<DoctorDirectoryEntry> doctors) async {
    if (!_valid || _submitting) return;
    Haptics.instance.medium();
    setState(() => _submitting = true);
    final doctor = doctors.firstWhere((d) => d.id == _doctorId,
        orElse: () => DoctorDirectoryEntry(id: _doctorId!, email: 'Doctor'));
    try {
      final appt = await AppointmentsService.instance.book(
        doctorId: _doctorId!,
        reportId: _reportId,
        scheduledFor: _combined!,
        durationMinutes: _duration,
        reason: _reasonCtrl.text.trim(),
      );
      SoundService.instance.success();
      Haptics.instance.success();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => _BookedDialog(doctorName: doctor.label, appt: appt),
      );
    } catch (e) {
      SoundService.instance.error();
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Themes.danger,
        content: Text(e is AppointmentException ? e.message : 'Could not book. Please try again.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeService.instance.isDark(context);
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.9;
    final reports = AppData.reports.value.where((r) => r.id != null).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: dark ? Themes.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 18 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: dark ? Themes.darkBorder : Themes.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Book an appointment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 4),
            Text('Request a slot with a verified dermatologist. They confirm it in their portal.',
                style: TextStyle(color: inkSoft, height: 1.35, fontSize: 13)),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Choose a doctor', ink),
                    const SizedBox(height: 8),
                    FutureBuilder<List<DoctorDirectoryEntry>>(
                      future: _doctors,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 22),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final doctors = snap.data ?? const <DoctorDirectoryEntry>[];
                        if (doctors.isEmpty) {
                          return Text('No verified doctors are available yet.',
                              style: TextStyle(color: inkSoft));
                        }
                        return Column(
                          children: [
                            for (final d in doctors) _doctorTile(d, dark),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _label('When', ink),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _pickerButton(
                            icon: Icons.calendar_today_rounded,
                            text: _date == null ? 'Pick a date' : _fmtDate(_date!),
                            dark: dark,
                            onTap: () => _pickDate(dark),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickerButton(
                            icon: Icons.access_time_rounded,
                            text: _time == null ? 'Pick a time' : _time!.format(context),
                            dark: dark,
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _label('Length', ink),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final m in [15, 30, 45, 60])
                          ChoiceChip(
                            label: Text('$m min'),
                            selected: _duration == m,
                            onSelected: (_) {
                              SoundService.instance.tap();
                              setState(() => _duration = m);
                            },
                          ),
                      ],
                    ),
                    if (reports.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _label('Link a screening (optional)', ink),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          _caseTile(null, 'No specific case', 'A general consultation', dark),
                          for (final r in reports)
                            _caseTile(r.id, r.condition,
                                '${_fmtDate(r.date)} · ${r.triage}', dark),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _label('Reason (optional)', ink),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: 'e.g. A mole on my arm has changed colour recently.',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: dark ? Themes.darkSurfaceDim : Themes.surfaceDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: FutureBuilder<List<DoctorDirectoryEntry>>(
                future: _doctors,
                builder: (context, snap) {
                  final doctors = snap.data ?? const <DoctorDirectoryEntry>[];
                  return FilledButton.icon(
                    onPressed: (!_valid || _submitting) ? null : () => _submit(doctors),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.event_available_rounded),
                    label: Text(_submitting ? 'Booking…' : 'Request appointment',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t, Color ink) =>
      Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: ink));

  Widget _doctorTile(DoctorDirectoryEntry d, bool dark) {
    final selected = d.id == _doctorId;
    final accent = dark ? Themes.tealGlow : Themes.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          SoundService.instance.tap();
          setState(() => _doctorId = d.id);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: dark ? 0.14 : 0.07)
                : (dark ? Themes.darkSurfaceDim : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? accent : (dark ? Themes.darkBorder : Themes.border),
                width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: dark ? 0.20 : 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.medical_services_outlined,
                  color: dark ? Themes.tealLight : Themes.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: dark ? Themes.darkInk : Themes.ink)),
                if ((d.regNo ?? '').isNotEmpty)
                  Text('Reg. ${d.regNo}',
                      style: TextStyle(
                          color: dark ? Themes.darkInkSoft : Themes.muted, fontSize: 12)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? accent : (dark ? Themes.darkInkSoft : Themes.muted), size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _caseTile(int? id, String title, String subtitle, bool dark) {
    final selected = id == _reportId;
    final accent = dark ? Themes.tealGlow : Themes.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          SoundService.instance.tap();
          setState(() => _reportId = id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: dark ? 0.14 : 0.07)
                : (dark ? Themes.darkSurfaceDim : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? accent : (dark ? Themes.darkBorder : Themes.border),
                width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(id == null ? Icons.chat_bubble_outline_rounded : Icons.description_outlined,
                size: 18, color: dark ? Themes.darkInkSoft : Themes.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: dark ? Themes.darkInk : Themes.ink)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: dark ? Themes.darkInkSoft : Themes.muted, fontSize: 11.8)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: accent, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _pickerButton({
    required IconData icon,
    required String text,
    required bool dark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: dark ? Themes.darkSurfaceDim : Themes.surfaceDim,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark ? Themes.darkBorder : Themes.border),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: dark ? Themes.tealLight : Themes.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: dark ? Themes.darkInk : Themes.ink)),
          ),
        ]),
      ),
    );
  }
}

/// Animated confirmation shown after a successful booking request.
class _BookedDialog extends StatefulWidget {
  const _BookedDialog({required this.doctorName, required this.appt});
  final String doctorName;
  final Appointment appt;

  @override
  State<_BookedDialog> createState() => _BookedDialogState();
}

class _BookedDialogState extends State<_BookedDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 640));
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)));
    _fade = CurvedAnimation(parent: _c, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeService.instance.isDark(context);
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final accent = dark ? Themes.tealLight : Themes.primary;
    return Dialog(
      backgroundColor: dark ? Themes.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF106E5A), Color(0xFF0B4639)],
                  ),
                ),
                child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 18),
            Text('Appointment requested',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fade,
              child: Column(
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(fontSize: 13.8, color: inkSoft, height: 1.4),
                      children: [
                        const TextSpan(text: 'Your request has been sent to '),
                        TextSpan(
                            text: widget.doctorName,
                            style: TextStyle(fontWeight: FontWeight.w700, color: accent)),
                        const TextSpan(text: '. You’ll be notified here once it’s approved.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: dark ? Themes.darkBorder : Themes.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 18, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_fmtDate(widget.appt.scheduledFor)} · ${_fmtTime(widget.appt.scheduledFor)}',
                            style: TextStyle(
                                fontSize: 13.2, fontWeight: FontWeight.w700, color: ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
