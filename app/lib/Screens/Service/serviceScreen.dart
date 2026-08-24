import 'package:flutter/material.dart';
import '../Doctors/nearbyDoctorsScreen.dart';
import '../Guide/skinGuideScreen.dart';
import '../theme.dart';

class ServiceScreen extends StatelessWidget {
  const ServiceScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Text(
            'Care & Tools',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: -0.01, shadows: Themes.onMedia),
          ),
          const SizedBox(height: 4),
          const Text(
            'Evidence-grounded tools to support your skin screening journey.',
            style: TextStyle(color: Themes.ink, fontSize: 13.5, height: 1.35, shadows: Themes.onMedia),
          ),
          const SizedBox(height: 20),
          _tile(
            context,
            Icons.location_on_outlined,
            'Where can I find a doctor?',
            'See verified dermatologists and skin clinics near you, nearest first.',
            false,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen())),
          ),
          _tile(
            context,
            Icons.menu_book_outlined,
            'Skin health guide',
            'Learn about photo quality, the ABCDE melanoma rule, sun protection and when to seek care.',
            false,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkinGuideScreen())),
          ),
          _tile(
            context,
            Icons.lock_outline_rounded,
            'Privacy & security',
            'Skin photos are sensitive health data. Images are only processed for screening and shared when you explicitly consent.',
            true,
          ),
          _tile(
            context,
            Icons.help_outline_rounded,
            'How screening works',
            'Photo → questionnaire → deep learning model → deterministic safety-aware triage result.',
            true,
          ),
        ],
      );

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String text,
    bool info, {
    VoidCallback? onTap,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        child: InkWell(
          onTap: onTap ??
              (info
                  ? () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          content: Text(text, style: const TextStyle(height: 1.4)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      )
                  : null),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Themes.brandTint.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  child: Icon(icon, color: Themes.brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Themes.ink)),
                      const SizedBox(height: 4),
                      Text(text, style: const TextStyle(color: Themes.inkSoft, height: 1.35, fontSize: 12.8)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Themes.inkMuted, size: 20),
              ],
            ),
          ),
        ),
      );
}

