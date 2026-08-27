import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../Screens/Home/homeScreen.dart';
import '../Screens/Reports/reportScreen.dart';
import '../Screens/Service/serviceScreen.dart';
import '../Screens/Upload/uploadScreen.dart';
import '../Screens/You/youScreen.dart';
import '../Screens/theme.dart';
import '../Screens/widgets/video_background.dart';
import '../Screens/widgets/floating_tab_bar.dart';
import '../Screens/widgets/slide_to_start.dart';
import '../services/self_exam_reminder.dart';
import '../services/sound_service.dart';

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

  // The four pill tabs; index 2 (New screening) is the standout accent action —
  // the "+" button set apart from the pill, exactly like the Neurotrace mock.
  static const _tabs = <NeuroTab>[
    NeuroTab(Icons.home_rounded, 0, 'Home'),
    NeuroTab(Icons.assignment_rounded, 1, 'Reports'),
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
                IconButton(onPressed: () => _showNotifications(context), icon: const Icon(Icons.notifications_none_rounded)),
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
                if (i != _currentIndex) SoundService.instance.tap();
                setState(() => _currentIndex = i);
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
    showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 30),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        SizedBox(height: 14),
        ListTile(leading: Icon(Icons.shield_outlined), title: Text('Your privacy matters'), subtitle: Text('Images should only be uploaded when you choose to screen.')),
        ListTile(leading: Icon(Icons.info_outline), title: Text('Screening reminder'), subtitle: Text('AI screening is informational and not a medical diagnosis.')),
      ]),
    ));
  }
}
