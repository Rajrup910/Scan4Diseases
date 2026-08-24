import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Screens/Doctors/nearbyDoctorsScreen.dart';
import '../Screens/theme.dart';
import 'nearby_doctors.dart';

/// Opens the device's maps app (or browser) searching for dermatologists near the user.
///
/// Deliberately no in-app location permission or Places API key: the maps app resolves
/// "near me" against its own location, which is simpler, keys-free, and privacy-preserving.
/// Tries the native `geo:` intent first, then falls back to a Google Maps web search.
Future<void> openNearbyDermatologists(BuildContext context) async {
  final candidates = <Uri>[
    Uri.parse('geo:0,0?q=dermatologist near me'),
    Uri.parse('https://www.google.com/maps/search/?api=1&query=dermatologist%20near%20me'),
  ];
  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Try the next candidate.
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open maps. Search "dermatologist near me" in your maps app.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Prominent call-to-action shown after every screening result, and reusable elsewhere.
///
/// Tapping the header expands an inline dropdown that loads nearby clinics from
/// OpenStreetMap (no Google API key, no cost) and lists them nearest-first with their
/// available stats — distance, specialty, open hours, phone, and a rating when the map
/// data happens to carry one. Tapping a clinic opens turn-by-turn directions from the
/// user's location straight to it.
class FindDoctorCard extends StatefulWidget {
  const FindDoctorCard({super.key, this.subtitle});

  /// Optional context line (e.g. tailored to the screening outcome).
  final String? subtitle;

  @override
  State<FindDoctorCard> createState() => _FindDoctorCardState();
}

class _FindDoctorCardState extends State<FindDoctorCard> {
  bool _expanded = false;
  Future<List<Clinic>>? _future; // lazily started on first expand

  static const int _inlineLimit = 6;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _future ??= NearbyDoctors.search();
    });
  }

  void _retry() => setState(() => _future = NearbyDoctors.search());

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: Themes.liquidGlassDecoration(radius: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: _dropdown(),
              crossFadeState:
                  _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      );

  // --- gradient header (the dropdown toggle) ---------------------------------

  Widget _header() => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Themes.brandTint.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  child: const Icon(Icons.location_on_outlined, color: Themes.brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Find a dermatologist near you',
                        style: TextStyle(
                            color: Themes.ink, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle ??
                            'Tap to see skin doctors and clinics close to you.',
                        style: const TextStyle(
                            color: Themes.inkSoft, height: 1.35, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Themes.brand, size: 24),
                ),
              ],
            ),
          ),
        ),
      );

  // --- expandable body -------------------------------------------------------

  Widget _dropdown() => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.50),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.85))),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: FutureBuilder<List<Clinic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Finding clinics near you…', style: TextStyle(color: Themes.muted)),
                ]),
              );
            }
            if (snap.hasError) return _error(snap.error);
            final clinics = snap.data ?? const <Clinic>[];
            if (clinics.isEmpty) {
              return _error(NearbyError('No clinics were listed near you.', 'empty'));
            }
            return _results(clinics);
          },
        ),
      );

  Widget _results(List<Clinic> clinics) {
    final shown = clinics.take(_inlineLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, right: 2, bottom: 10),
          child: Text(
            'Nearest first. Tap a clinic to get directions from your location.',
            style: TextStyle(color: Themes.muted, fontSize: 12, height: 1.35),
          ),
        ),
        for (final c in shown) ...[
          _clinicRow(c),
          const SizedBox(height: 10),
        ],
        Row(children: [
          if (clinics.length > shown.length)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen()),
                ),
                icon: const Icon(Icons.list_rounded, size: 18),
                label: Text('See all ${clinics.length}'),
              ),
            ),
          if (clinics.length > shown.length) const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => openNearbyDermatologists(context),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open Maps'),
            ),
          ),
        ]),
      ],
    );
  }

  // --- one clinic (tap → directions) -----------------------------------------

  Widget _clinicRow(Clinic c) {
    final accent = c.isDermatology ? Themes.primary : Themes.mint;
    return Material(
      color: Themes.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => NearbyDoctors.directionsTo(c),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                c.isDermatology
                    ? Icons.medical_services_outlined
                    : Icons.local_hospital_outlined,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip(Icons.place_outlined, '${c.distanceLabel} · ${c.proximityLabel}',
                      accent),
                  _chip(c.isDermatology ? Icons.verified_outlined : Icons.local_hospital_outlined,
                      c.kind, accent),
                  if (c.hasRating)
                    _chip(Icons.star_rounded, c.rating!.toStringAsFixed(1),
                        Themes.warning),
                  if (c.openingHours != null && c.openingHours!.length <= 18)
                    _chip(Icons.schedule_rounded, c.openingHours!, Themes.muted),
                  if (c.phone != null) _chip(Icons.call_outlined, 'Phone', Themes.muted),
                ]),
                if (c.address != null) ...[
                  const SizedBox(height: 6),
                  Text(c.address!,
                      style: const TextStyle(color: Themes.muted, fontSize: 12.5)),
                ],
              ]),
            ),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.directions_rounded, color: Themes.primary),
              SizedBox(height: 2),
              Text('Directions',
                  style: TextStyle(
                      color: Themes.primary, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  // --- error / empty ---------------------------------------------------------

  Widget _error(Object? error) {
    final ne = error is NearbyError ? error : NearbyError('Something went wrong.', 'network');
    final icon = switch (ne.kind) {
      'permission' => Icons.location_disabled_rounded,
      'service_off' => Icons.location_off_rounded,
      'empty' => Icons.search_off_rounded,
      _ => Icons.wifi_off_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(children: [
        Icon(icon, size: 40, color: Themes.muted),
        const SizedBox(height: 12),
        Text(ne.message, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => openNearbyDermatologists(context),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open Maps'),
            ),
          ),
        ]),
      ]),
    );
  }
}
