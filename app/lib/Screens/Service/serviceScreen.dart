import 'package:flutter/material.dart';
import '../Appointments/appointmentsScreen.dart';
import '../Doctors/knowYourDoctorScreen.dart';
import '../Doctors/nearbyDoctorsScreen.dart';
import '../Guide/skinGuideScreen.dart';
import '../theme.dart';
import '../../services/appointments_service.dart';
import '../../services/sound_service.dart';
import '../../services/theme_service.dart';

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  @override
  void initState() {
    super.initState();
    // Keep the "your doctor responded" badge on the appointments tile current.
    AppointmentsService.instance.refreshUnread();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.instance.mode,
        builder: (_, __, ___) {
          final dark = ThemeService.instance.isDark(context);
          final ink = dark ? Themes.darkInk : Themes.ink;
          final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Frosted pill so the tab header reads over the moving backdrop
              // instead of ghosting out as a bare heading. Uses the same helper
              // Profile does — one source of truth for section chrome.
              Align(
                alignment: Alignment.centerLeft,
                child: Themes.sectionHeaderPill('Care & Tools',
                    dark: dark, icon: Icons.dashboard_customize_rounded),
              ),
              const SizedBox(height: 10),
              Text(
                'Evidence-grounded tools to support your skin screening journey.',
                style: TextStyle(
                  color: ink,
                  fontSize: 13.5,
                  height: 1.35,
                  shadows: dark ? Themes.onMediaDark : Themes.onMedia,
                ),
              ),
              const SizedBox(height: 20),
              // Book an appointment — the primary care action, with a live badge
              // when the doctor has approved / declined / recommended a visit.
              ValueListenableBuilder<int>(
                valueListenable: AppointmentsService.instance.unread,
                builder: (_, unread, __) => _tile(
                  context,
                  Icons.event_available_rounded,
                  'Book an appointment',
                  'Request a consultation with a verified dermatologist, or review a visit your doctor recommended.',
                  false,
                  dark,
                  badge: unread,
                  onTap: () {
                    SoundService.instance.open();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AppointmentsScreen()),
                    );
                  },
                ),
              ),
              _tile(
                context,
                Icons.verified_user_outlined,
                'Know your doctor',
                'Meet your verified clinical dermatologists, their medical credentials, registration, and clinical focus areas.',
                false,
                dark,
                onTap: () {
                  SoundService.instance.open();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const KnowYourDoctorScreen()),
                  );
                },
              ),
              _tile(
                context,
                Icons.location_on_outlined,
                'Where can I find a doctor?',
                'See verified dermatologists and skin clinics near you, nearest first.',
                false,
                dark,
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen())),
              ),
              _tile(
                context,
                Icons.menu_book_outlined,
                'Skin health guide',
                'Learn about photo quality, the ABCDE melanoma rule, sun protection and when to seek care.',
                false,
                dark,
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SkinGuideScreen())),
              ),
              _tile(
                context,
                Icons.lock_outline_rounded,
                'Privacy & security',
                'Skin photos are sensitive health data. Images are only processed for screening and shared when you explicitly consent.',
                true,
                dark,
              ),
              _tile(
                context,
                Icons.help_outline_rounded,
                'How screening works',
                'Photo → questionnaire → deep learning model → deterministic safety-aware triage result.',
                true,
                dark,
              ),
              const SizedBox(height: 8),
              // Small caption that hangs beneath the last card — kept legible
              // over the backdrop with the dark text-halo shadow.
              Text(
                'Actionable Health · lifestyle guidance and a shared clinical report',
                style: TextStyle(
                  color: inkSoft,
                  fontSize: 11.5,
                  height: 1.4,
                  shadows: dark ? Themes.onMediaDark : Themes.onMedia,
                ),
              ),
            ],
          );
        },
      );

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String text,
    bool info,
    bool dark, {
    VoidCallback? onTap,
    int badge = 0,
  }) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final chev = dark ? Themes.darkInkSoft : Themes.inkMuted;
    final accent = dark ? Themes.tealLight : Themes.brand;
    final tile = dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.70);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: dark
          ? Themes.liquidGlassDecoration(radius: 18, dark: true, topAlpha: 0.85, bottomAlpha: 0.70)
          : Themes.liquidGlassDecoration(radius: 18),
      child: Material(
        color: Colors.transparent,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tile,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: dark
                              ? Themes.tealGlow.withValues(alpha: 0.27)
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 18),
                          decoration: BoxDecoration(
                            color: Themes.danger,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: dark ? Themes.darkSurface : Colors.white, width: 1.5),
                          ),
                          child: Text(
                            '$badge',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ink)),
                      const SizedBox(height: 4),
                      Text(text,
                          style: TextStyle(color: inkSoft, height: 1.35, fontSize: 12.8)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: chev, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
