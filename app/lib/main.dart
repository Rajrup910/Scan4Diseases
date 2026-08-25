import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'LandingPage/landingPage.dart';
import 'Screens/Auth/authGate.dart';
import 'Screens/theme.dart';
import 'services/auth_service.dart';
import 'services/language_service.dart';
import 'services/motion_service.dart';
import 'services/self_exam_reminder.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the remembered session, language, and appearance choice before the
  // first frame, so the app opens straight to the home shell (for a signed-in
  // user) in their language and their last-used light/dark theme.
  await ApiConfig.loadPersisted();
  await AuthService.instance.restore();
  await LanguageService.instance.load();
  await ThemeService.instance.load();
  await MotionService.instance.load();
  await SelfExamReminder.load();
  runApp(const Scan4DiseasesApp());
}

class Scan4DiseasesApp extends StatelessWidget {
  const Scan4DiseasesApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: ThemeService.instance.mode,
    builder: (_, mode, __) => MaterialApp(
      title: 'Scan4Diseases', debugShowCheckedModeBanner: false,
      theme: Themes.lightTheme,
      darkTheme: Themes.darkTheme,
      themeMode: mode,
      home: const AuthGate(child: LandingShell()),
    ),
  );
}

class LandingShell extends StatefulWidget { const LandingShell({super.key}); @override State<LandingShell> createState() => _LandingShellState(); }
class _LandingShellState extends State<LandingShell> {
  CameraDescription? camera;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final c = await availableCameras(); if (mounted && c.isNotEmpty) setState(() => camera = c.first); } catch (_) {} }
  @override Widget build(BuildContext context) => MyLandingPage(firstCam: camera);
}
