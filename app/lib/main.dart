import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'LandingPage/landingPage.dart';
import 'Screens/Auth/authGate.dart';
import 'Screens/theme.dart';
import 'services/auth_service.dart';
import 'services/language_service.dart';
import 'services/self_exam_reminder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the remembered session and language choice before the first frame, so
  // the app opens straight to the home shell (for a signed-in user) in their language.
  await ApiConfig.loadPersisted();
  await AuthService.instance.restore();
  await LanguageService.instance.load();
  await SelfExamReminder.load();
  runApp(const DermaScreenApp());
}

class DermaScreenApp extends StatelessWidget {
  const DermaScreenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DermaScreen', debugShowCheckedModeBanner: false,
    theme: Themes.lightTheme,
    home: const AuthGate(child: LandingShell()),
  );
}

class LandingShell extends StatefulWidget { const LandingShell({super.key}); @override State<LandingShell> createState() => _LandingShellState(); }
class _LandingShellState extends State<LandingShell> {
  CameraDescription? camera;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final c = await availableCameras(); if (mounted && c.isNotEmpty) setState(() => camera = c.first); } catch (_) {} }
  @override Widget build(BuildContext context) => MyLandingPage(firstCam: camera);
}
