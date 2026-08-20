import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../Screens/Home/homeScreen.dart';
import '../Screens/Reports/reportScreen.dart';
import '../Screens/Service/serviceScreen.dart';
import '../Screens/Upload/uploadScreen.dart';
import '../Screens/You/youScreen.dart';
import '../Screens/theme.dart';
import '../services/self_exam_reminder.dart';

class MyLandingPage extends StatefulWidget {
  final CameraDescription? firstCam;
  const MyLandingPage({super.key, this.firstCam});
  @override State<MyLandingPage> createState() => _MyLandingPageState();
}

class _MyLandingPageState extends State<MyLandingPage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Surface the monthly self-exam reminder once, after the first frame, when it's due.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowSelfExamReminder());
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
  final _items = const [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: 'Reports'),
    BottomNavigationBarItem(icon: Icon(Icons.add_a_photo_rounded), label: 'Screen'),
    BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Services'),
    BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final children = [
      HomeScreen(
        onStart: () => setState(() => _currentIndex = 2),
        onOpenReports: () => setState(() => _currentIndex = 1),
      ),
      const ReportScreen(),
      UploadScreen(camera: widget.firstCam),
      const ServiceScreen(),
      const YouScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex], style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: () => _showNotifications(context), icon: const Icon(Icons.notifications_none_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _currentIndex, children: children)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _items.map((e) => NavigationDestination(icon: e.icon, label: e.label!)).toList(),
        indicatorColor: Themes.primary.withOpacity(.12),
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
