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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: Themes.liquidGlassDecoration(radius: 20, dark: dark),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(dark),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _dropdown(dark),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  // --- gradient header (the dropdown toggle) ---------------------------------

  Widget _header(bool dark) => Material(
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
                    color: (dark ? Themes.tealGlow : Themes.brand).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: dark
                          ? Themes.tealGlow.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  child: Icon(Icons.location_on_outlined, color: dark ? Themes.tealLight : Themes.brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find a dermatologist near you',
                        style: TextStyle(
                          color: dark ? Themes.darkInk : Themes.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle ??
                            'Tap to see skin doctors and clinics close to you.',
                        style: TextStyle(
                          color: dark ? Themes.darkInkSoft : Themes.inkSoft,
                          height: 1.35,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: dark ? Themes.tealLight : Themes.brand,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // --- expandable body -------------------------------------------------------

  Widget _dropdown(bool dark) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: dark ? Themes.darkSurface.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.50),
          border: Border(
            top: BorderSide(
              color: dark ? Themes.darkBorder : Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: FutureBuilder<List<Clinic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Finding clinics near you…',
                      style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.muted)),
                ]),
              );
            }
            if (snap.hasError) return _error(snap.error, dark);
            final clinics = snap.data ?? const <Clinic>[];
            if (clinics.isEmpty) {
              return _error(NearbyError('No clinics were listed near you.', 'empty'), dark);
            }
            return _results(clinics, dark);
          },
        ),
      );

  Widget _results(List<Clinic> clinics, bool dark) {
    final shown = clinics.take(_inlineLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
          child: Text(
            'Nearest first. Tap a clinic to get directions from your location.',
            style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.muted, fontSize: 12, height: 1.35),
          ),
        ),
        for (final c in shown) ...[
          _clinicRow(c, dark),
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

  Widget _clinicRow(Clinic c, bool dark) {
    final accent = c.isDermatology
        ? (dark ? Themes.tealGlow : Themes.primary)
        : (dark ? Themes.tealLight : Themes.mint);
    return Material(
      color: dark ? const Color(0xFF1E2430) : Themes.surface,
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
                color: accent.withValues(alpha: dark ? 0.20 : 0.12),
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
                Text(
                  c.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: dark ? Themes.darkInk : Themes.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip(Icons.place_outlined, '${c.distanceLabel} · ${c.proximityLabel}', accent, dark),
                  _chip(c.isDermatology ? Icons.verified_outlined : Icons.local_hospital_outlined, c.kind, accent, dark),
                  if (c.hasRating)
                    _chip(Icons.star_rounded, c.rating!.toStringAsFixed(1), Themes.warning, dark),
                  if (c.openingHours != null && c.openingHours!.length <= 18)
                    _chip(Icons.schedule_rounded, c.openingHours!, Themes.muted, dark),
                  if (c.phone != null) _chip(Icons.call_outlined, 'Phone', Themes.muted, dark),
                ]),
                if (c.address != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    c.address!,
                    style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.muted, fontSize: 12.5),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.directions_rounded, color: dark ? Themes.tealLight : Themes.primary),
              const SizedBox(height: 2),
              Text(
                'Directions',
                style: TextStyle(
                  color: dark ? Themes.tealLight : Themes.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color, bool dark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.20 : 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: dark && color == Themes.muted ? Themes.darkInkSoft : color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: dark && color == Themes.muted ? Themes.darkInkSoft : (dark && color == Themes.primary ? Themes.tealLight : color),
            ),
          ),
        ]),
      );

  // --- error / empty ---------------------------------------------------------

  Widget _error(Object? error, bool dark) {
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
        Icon(icon, size: 40, color: dark ? Themes.darkInkSoft : Themes.muted),
        const SizedBox(height: 12),
        Text(ne.message,
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4, color: dark ? Themes.darkInk : Themes.ink)),
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
