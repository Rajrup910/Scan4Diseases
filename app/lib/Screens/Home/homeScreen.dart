import 'package:flutter/material.dart';
import '../../services/find_doctor.dart';
import '../Guide/skinGuideScreen.dart';
import '../theme.dart';
import '../app_data.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onStart;

  /// Switches the shell to the Reports tab. Previously this popped the route, which did
  /// nothing from inside the tab shell.
  final VoidCallback onOpenReports;

  const HomeScreen({super.key, required this.onStart, required this.onOpenReports});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ScreeningReport>>(
      valueListenable: AppData.reports,
      builder: (_, reports, __) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const Text('Good morning 👋', style: TextStyle(color: Themes.muted, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Take care of your skin.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Themes.ink)),
          const SizedBox(height: 20),
          _hero(context),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _stat(Icons.assignment_turned_in_outlined, '${reports.length}', 'Screenings')),
            const SizedBox(width: 12),
            Expanded(child: _stat(Icons.verified_user_outlined, 'AI', 'Assisted')),
          ]),
          const SizedBox(height: 22),
          const Text('Quick actions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _action(Icons.camera_alt_rounded, 'New screening', 'Upload a photo', onStart)),
            const SizedBox(width: 12),
            Expanded(child: _action(Icons.history_rounded, 'My screenings', 'Review results', onOpenReports)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _action(Icons.menu_book_rounded, 'Skin care guide', 'Learn & self-check',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkinGuideScreen())))),
            const SizedBox(width: 12),
            Expanded(child: _action(Icons.location_on_rounded, 'Find a doctor', 'Clinics near you',
                () => openNearbyDermatologists(context))),
          ]),
          const SizedBox(height: 22),
          const _SafetyCard(),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Themes.primary, Themes.primaryDark]),
      borderRadius: BorderRadius.circular(26),
      boxShadow: [BoxShadow(color: Themes.primary.withOpacity(.22), blurRadius: 24, offset: const Offset(0, 12))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 36),
      const SizedBox(height: 18),
      const Text('AI-assisted skin screening', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('Upload a clear skin image and answer a few questions to get a preliminary screening.', style: TextStyle(color: Colors.white.withOpacity(.86), height: 1.4)),
      const SizedBox(height: 18),
      FilledButton(onPressed: onStart, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Themes.primary), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Start screening'))),
    ]),
  );

  Widget _stat(IconData icon, String value, String label) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Themes.border)), child: Row(children: [Icon(icon, color: Themes.primary), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(label, style: const TextStyle(color: Themes.muted))]) ]));

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Themes.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Themes.primary.withOpacity(.1), shape: BoxShape.circle), child: Icon(icon, color: Themes.primary)), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Themes.muted, fontSize: 12))])));
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: const Color(0xFFFFF8E8), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF6D98C))), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline_rounded, color: Themes.warning), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Important', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('This app provides AI-assisted screening only. It cannot replace a qualified dermatologist.', style: TextStyle(color: Themes.ink, height: 1.35))]))]));
}
