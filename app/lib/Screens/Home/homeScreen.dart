import 'dart:async';
import 'package:flutter/material.dart';
import '../Doctors/nearbyDoctorsScreen.dart';
import '../Guide/skinGuideScreen.dart';
import '../theme.dart';
import '../app_data.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/emerald_waves.dart';
import '../widgets/slide_to_start.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onStart;

  /// Switches the shell to the Reports tab.
  final VoidCallback onOpenReports;

  const HomeScreen({super.key, required this.onStart, required this.onOpenReports});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ScreeningReport>>(
      valueListenable: AppData.reports,
      builder: (_, reports, __) {
        // Build the top-level list as raw widgets, then wrap each in a small
        // stagger-in helper so the home shell settles gently rather than
        // snapping in as one flat block. 30ms per row → the whole shell is in
        // place under ~350ms.
        final rawChildren = <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Brand mark — glowing electric teal emblem (twin of the web mark).
              const AppLogoMark(size: 26, glow: true),
              const SizedBox(width: 8),
              const Text(
                'Scan4Disease Mobile',
                style: TextStyle(color: Themes.ink, fontSize: 13, fontWeight: FontWeight.w600, shadows: Themes.onMedia),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Take care of your skin.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: -0.02, shadows: Themes.onMedia),
          ),
          const SizedBox(height: 18),
          _hero(context),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _stat(Icons.assignment_turned_in_outlined, '${reports.length}', 'Saved screenings')),
            const SizedBox(width: 12),
            Expanded(child: _stat(Icons.verified_user_outlined, 'AI', 'Screening support')),
          ]),
          if (reports.isNotEmpty) ...[
            const SizedBox(height: 20),
            _recentSpotlight(context, reports.first),
          ],
          const SizedBox(height: 24),
          const Text(
            'Quick actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: -0.01, shadows: Themes.onMedia),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _action(Icons.camera_alt_rounded, 'New screening', 'Photo & triage', onStart)),
            const SizedBox(width: 12),
            Expanded(child: _action(Icons.history_rounded, 'My screenings', 'Review records', onOpenReports)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _action(Icons.menu_book_rounded, 'Skin health guide', 'Learn & ABCDE',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkinGuideScreen())))),
            const SizedBox(width: 12),
            Expanded(child: _action(Icons.location_on_rounded, 'Find a doctor', 'Clinics near you',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen())))),
          ]),
          const SizedBox(height: 20),
          _uvAdvisoryCard(context),
          const SizedBox(height: 20),
          const _SafetyCard(),
        ];
        // Preserve spacer SizedBoxes as-is (no animation needed for empty
        // spans), but stagger substantive children by their content index.
        var contentIndex = 0;
        final staggered = <Widget>[
          for (final w in rawChildren)
            if (w is SizedBox) w
            else _StaggerIn(index: contentIndex++, child: w),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: staggered,
        );
      },
    );
  }

  Widget _recentSpotlight(BuildContext context, ScreeningReport r) {
    final triageLower = r.triage.toLowerCase();
    final triageColor = triageLower.contains('urgent')
        ? Themes.urgent
        : triageLower.contains('prompt') || triageLower.contains('soon')
            ? Themes.soon
            : Themes.routine;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenReports,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Themes.brandTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, size: 16, color: Themes.brand),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Latest screening spotlight',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Themes.inkSoft),
                  ),
                  const Spacer(),
                  const Text('View all →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Themes.brand)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.condition,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Themes.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Screened ${_date(r.date)}',
                          style: const TextStyle(fontSize: 12.5, color: Themes.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: triageColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: triageColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      r.triage,
                      style: TextStyle(color: triageColor, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uvAdvisoryCard(BuildContext context) {
    final hour = DateTime.now().hour;
    final isPeakUv = hour >= 10 && hour <= 16;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPeakUv ? Themes.warningTint : Themes.brandTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isPeakUv ? Icons.wb_sunny_rounded : Icons.wb_twilight_rounded,
                color: isPeakUv ? Themes.warning : Themes.brand,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPeakUv ? 'Peak UV Hours (10 AM - 4 PM)' : 'Sun Safety & UV Protection',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Themes.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isPeakUv
                        ? 'Sun exposure is intense right now. Use SPF 30+, seek shade, and wear protective clothing.'
                        : 'Routine UV protection reduces skin damage and long-term risk. Check the ABCDE guide.',
                    style: const TextStyle(color: Themes.inkSoft, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _hero(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Themes.brand.withValues(alpha: 0.35),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.20),
          blurRadius: 4,
          spreadRadius: 0.5,
        ),
      ],
    ),
    child: EmeraldWaves(
      borderRadius: BorderRadius.circular(22),
      reverse: false,
      speedMultiplier: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Clinical AI Tool',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'AI-assisted skin screening',
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.01),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload a clear skin photo and answer symptoms for an immediate evidence-grounded preliminary assessment.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.88), height: 1.4, fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            // Slide-to-start — dragging the thumb to the end fires onStart (opposite wave motion).
            SlideToStart(label: 'New screening', onComplete: onStart),
          ],
        ),
      ),
    ),
  );

  Widget _stat(IconData icon, String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: Themes.liquidGlassDecoration(radius: 18),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Themes.brandTint.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
          ),
          child: Icon(icon, color: Themes.brand, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Themes.ink)),
              Text(label, style: const TextStyle(color: Themes.inkSoft, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Themes.brandTint.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
              ),
              child: Icon(icon, color: Themes.brand, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Themes.ink)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Themes.inkSoft, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

/// Fades and glides a widget in with a per-index delay. Used to stagger the
/// home shell's top-level rows so nothing snaps in as one flat block. Cheap:
/// one AnimationController per row, disposed on unmount, and no-op once done.
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _kick;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _kick = Timer(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _kick?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeOutCubic.transform(_c.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: child,
            ),
          );
        },
        child: widget.child,
      );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Themes.warningTint.withValues(alpha: 0.85),
          Themes.warningTint.withValues(alpha: 0.65),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.50),
          blurRadius: 3,
          spreadRadius: 0.5,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Themes.warning, size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clinical disclaimer',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Themes.soon),
              ),
              SizedBox(height: 3),
              Text(
                'This app provides AI-assisted screening only — not a formal medical diagnosis. Always consult a qualified dermatologist.',
                style: TextStyle(color: Themes.ink, height: 1.35, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

