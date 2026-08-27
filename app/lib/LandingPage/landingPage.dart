import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../Screens/Appointments/appointmentsScreen.dart';
import '../Screens/Home/homeScreen.dart';
import '../Screens/Reports/reportScreen.dart';
import '../Screens/Service/serviceScreen.dart';
import '../Screens/Upload/uploadScreen.dart';
import '../Screens/You/youScreen.dart';
import '../Screens/theme.dart';
import '../Screens/widgets/video_background.dart';
import '../Screens/widgets/floating_tab_bar.dart';
import '../Screens/widgets/slide_to_start.dart';
import '../services/app_notifications.dart';
import '../services/appointments_service.dart';
import '../services/haptics_service.dart';
import '../services/self_exam_reminder.dart';

class MyLandingPage extends StatefulWidget {
  final CameraDescription? firstCam;
  const MyLandingPage({super.key, this.firstCam});
  @override State<MyLandingPage> createState() => _MyLandingPageState();
}

class _MyLandingPageState extends State<MyLandingPage> {
  int _currentIndex = 0;
  bool _startWash = false;

  @override
  void initState() {
    super.initState();
    // Surface the monthly self-exam reminder once, after the first frame, when it's due.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowSelfExamReminder());
    // Pull appointments so the top-bar bell can reflect any doctor responses
    // (approvals, cancellations, recommendations) as soon as the app opens.
    AppointmentsService.instance.refresh();
  }

  /// Index reserved for the dedicated Appointments window. It isn't a body tab
  /// (the screen brings its own Scaffold) — selecting it pushes a full route.
  static const int _appointmentsTab = 5;

  void _openAppointments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppointmentsScreen()),
    );
  }

  /// The Home slide-to-start action fires this: the whole mobile screen turns
  /// green (a full-viewport gradient wash), and once the wash reaches full
  /// opacity we swap to the Upload tab and reverse the wash back out.
  void _triggerStartScreeningTransition() {
    if (_startWash) return;
    setState(() => _startWash = true);
  }

  void _onWashPeak() {
    // Crest reached: swap tab cleanly while obscured under the lush brand veil
    setState(() => _currentIndex = 2);
  }

  void _onWashComplete() {
    if (mounted) setState(() => _startWash = false);
  }

  Future<void> _maybeShowSelfExamReminder() async {
    if (!SelfExamReminder.isDue || !mounted) return;
    // Roll the next reminder forward so this prompt only appears once per period.
    await SelfExamReminder.scheduleNext();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_available_outlined, color: Themes.mint, size: 32),
        title: const Text('Time for a skin self-check'),
        content: const Text(
          'It’s been about a month. Take 5 minutes to check your skin head to toe, '
          'and note anything new or changing.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _currentIndex = 3); // Care & Tools tab
            },
            child: const Text('Open guide'),
          ),
        ],
      ),
    );
  }

  // Reports, New Screening and Care & Tools each render their own large header in-body,
  // so the app-bar title is left blank there to avoid showing the title twice.
  final _titles = ['Home', '', '', '', 'Profile'];

  // The pill tabs; index 2 (New screening) is the standout accent action — the
  // "+" button set apart from the pill, exactly like the Neurotrace mock. Index
  // 5 (Appointments) opens its own full-screen window rather than a body tab.
  static const _tabs = <NeuroTab>[
    NeuroTab(Icons.home_rounded, 0, 'Home'),
    NeuroTab(Icons.assignment_rounded, 1, 'Reports'),
    NeuroTab(Icons.calendar_month_rounded, _appointmentsTab, 'Appointments'),
    NeuroTab(Icons.grid_view_rounded, 3, 'Services'),
    NeuroTab(Icons.person_rounded, 4, 'Profile'),
  ];
  static const _action = NeuroTab(Icons.add_rounded, 2, 'New screening');

  @override
  Widget build(BuildContext context) {
    final children = [
      HomeScreen(
        onStart: _triggerStartScreeningTransition,
        onOpenReports: () => setState(() => _currentIndex = 1),
      ),
      const ReportScreen(),
      UploadScreen(camera: widget.firstCam),
      const ServiceScreen(),
      const YouScreen(),
    ];
    // The live video backdrop sits behind the whole shell so the motion carries
    // through every tab; the frosted bar and content float over it. Falls back to
    // the painted blueprint background if the clip can't play.
    return VideoBackground(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(_titles[_currentIndex], style: const TextStyle(fontWeight: FontWeight.w700)),
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: AppNotifications.instance.unread,
                  builder: (_, count, __) => IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => _showNotifications(context),
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      backgroundColor: Themes.urgent,
                      child: Icon(count > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            // Fade-through between tabs instead of a hard IndexedStack swap.
            //
            // Every child stays mounted, so state survives the switch (scroll
            // offsets, form input, chat history, the running video backdrop).
            // Rather than a plain crossfade — where both tabs are half-visible
            // in the middle and the content muddles — this follows the Material
            // fade-through shape: the outgoing tab clears out over the first
            // ~35% of the 300ms, then the incoming one rises over the
            // remainder while scaling 0.97 → 1.0. Hand-rolled with interval
            // curves so the app takes no extra package dependency.
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: List.generate(children.length, (i) {
                  final isActive = i == _currentIndex;
                  return IgnorePointer(
                    ignoring: !isActive,
                    child: AnimatedOpacity(
                      opacity: isActive ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      // Incoming waits out the outgoing tab's exit; outgoing
                      // leaves promptly. The two intervals are what turn a
                      // crossfade into a fade-through.
                      curve: isActive
                          ? const Interval(0.35, 1.0, curve: Curves.easeOutCubic)
                          : const Interval(0.0, 0.35, curve: Curves.easeInCubic),
                      child: AnimatedScale(
                        scale: isActive ? 1.0 : 0.97,
                        duration: const Duration(milliseconds: 300),
                        curve: isActive
                            ? const Interval(0.35, 1.0, curve: Curves.easeOutCubic)
                            : const Interval(0.0, 0.35, curve: Curves.easeInCubic),
                        child: children[i],
                      ),
                    ),
                  );
                }),
              ),
            ),
            bottomNavigationBar: FloatingTabBar(
              currentIndex: _currentIndex,
              onSelect: (i) {
                // Switching tabs is routine navigation: a subtle haptic tick
                // only — no click sound (the old tap cue on every tab press was
                // the "sound on every click" the audit flagged). Haptics fire
                // independently of the sound preference.
                Haptics.instance.selection();
                // Appointments is a dedicated window, not a body tab.
                if (i == _appointmentsTab) {
                  _openAppointments();
                  return;
                }
                if (i != _currentIndex) setState(() => _currentIndex = i);
              },
              tabs: _tabs,
              action: _action,
            ),
          ),
          // Full-viewport green wash — covers appbar, body, and tab bar during
          // the slide-to-start hand-off from Home to the screening flow.
          Positioned.fill(
            child: ScreenWash(
              active: _startWash,
              onWashPeak: _onWashPeak,
              onWashComplete: _onWashComplete,
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    // Refresh appointments so the feed reflects the latest doctor responses,
    // then present the notification centre. Opening it clears the badge.
    AppointmentsService.instance.refresh();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        // Mark read after the sheet is built so the badge clears once opened.
        WidgetsBinding.instance.addPostFrameCallback((_) => AppNotifications.instance.markAllRead());
        final dark = Theme.of(sheetCtx).brightness == Brightness.dark;
        final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => ValueListenableBuilder<List<AppNotification>>(
            valueListenable: AppNotifications.instance.items,
            builder: (_, notes, __) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
              children: [
                Row(
                  children: [
                    const Text('Notifications',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (notes.isNotEmpty)
                      TextButton.icon(
                        onPressed: _openAppointments,
                        icon: const Icon(Icons.calendar_month_rounded, size: 18),
                        label: const Text('Appointments'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(children: [
                      Icon(Icons.notifications_off_outlined, size: 40, color: inkSoft),
                      const SizedBox(height: 10),
                      Text("You're all caught up",
                          style: TextStyle(fontWeight: FontWeight.w700, color: inkSoft)),
                      const SizedBox(height: 4),
                      Text(
                        'Approvals, cancellations and visits your doctor recommends will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: inkSoft, height: 1.4),
                      ),
                    ]),
                  )
                else
                  for (final n in notes) _notificationTile(n, dark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _notificationTile(AppNotification n, bool dark) {
    final (icon, color) = _noteStyle(n.kind, dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: dark ? 0.20 : 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(n.title,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: dark ? Themes.darkInk : Themes.ink)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(n.body,
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: dark ? Themes.darkInkSoft : Themes.inkSoft)),
        ),
        onTap: n.appointmentId != null
            ? () {
                Navigator.pop(context);
                _openAppointments();
              }
            : null,
      ),
    );
  }

  (IconData, Color) _noteStyle(String kind, bool dark) {
    switch (kind) {
      case 'approved':
        return (Icons.event_available_rounded, dark ? Themes.tealLight : Themes.routine);
      case 'recommended':
        return (Icons.medical_services_rounded, dark ? Themes.tealLight : Themes.brand);
      case 'requested':
        return (Icons.schedule_send_rounded, Themes.soon);
      case 'declined':
        return (Icons.event_busy_rounded, Themes.danger);
      case 'cancelled':
        return (Icons.cancel_rounded, Themes.danger);
      case 'reminder':
        return (Icons.notifications_active_rounded, dark ? Themes.tealLight : Themes.brand);
      default:
        return (Icons.info_outline_rounded, dark ? Themes.darkInkSoft : Themes.inkSoft);
    }
  }
}
