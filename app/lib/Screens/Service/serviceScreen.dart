import 'package:flutter/material.dart';
import '../../services/find_doctor.dart';
import '../Guide/skinGuideScreen.dart';
import '../theme.dart';

class ServiceScreen extends StatelessWidget {
  const ServiceScreen({super.key});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Care & Tools', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    const Text('Helpful tools around your screening journey.', style: TextStyle(color: Themes.muted)),
    const SizedBox(height: 20),
    _tile(context, Icons.location_on_outlined, 'Where can I find a doctor?', 'Open maps to find dermatologists and skin clinics near you.', false, onTap: () => openNearbyDermatologists(context)),
    _tile(context, Icons.menu_book_outlined, 'Skin health guide', 'Learn about image quality, sun protection and when to seek care.', false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkinGuideScreen()))),
    _tile(context, Icons.lock_outline_rounded, 'Privacy', 'Skin photos are sensitive. Only upload images you are comfortable sharing.', true),
    _tile(context, Icons.help_outline_rounded, 'How screening works', 'Photo → questionnaire → AI model → safety-aware result.', true),
  ]);

  Widget _tile(BuildContext context, IconData icon, String title, String text, bool info, {VoidCallback? onTap}) => Card(margin: const EdgeInsets.only(bottom: 12), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap ?? (info ? () => showDialog(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])) : null), child: Padding(padding: const EdgeInsets.all(17), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: Themes.primary.withOpacity(.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Themes.primary)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 5), Text(text, style: const TextStyle(color: Themes.muted, height: 1.35))]))]))));
}
