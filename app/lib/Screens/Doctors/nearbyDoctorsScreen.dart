import 'package:flutter/material.dart';

import '../../services/find_doctor.dart';
import '../../services/nearby_doctors.dart';
import '../theme.dart';

/// In-app list of nearby doctors/clinics from OpenStreetMap, nearest first (dermatology
/// matches promoted). Tapping a row opens turn-by-turn directions. A "Google Maps" action
/// is always available as a fallback, since OSM coverage is thin in some areas.
class NearbyDoctorsScreen extends StatefulWidget {
  const NearbyDoctorsScreen({super.key});

  @override
  State<NearbyDoctorsScreen> createState() => _NearbyDoctorsScreenState();
}

class _NearbyDoctorsScreenState extends State<NearbyDoctorsScreen> {
  late Future<List<Clinic>> _future;

  @override
  void initState() {
    super.initState();
    _future = NearbyDoctors.search();
  }

  void _retry() => setState(() => _future = NearbyDoctors.search());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dermatologists near you'),
        actions: [
          IconButton(
            tooltip: 'Open in Google Maps',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => openNearbyDermatologists(context),
          ),
        ],
      ),
      body: FutureBuilder<List<Clinic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _Centered(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Finding clinics near you…', style: TextStyle(color: Themes.muted)),
              ]),
            );
          }
          if (snap.hasError) {
            return _error(snap.error);
          }
          final clinics = snap.data ?? const [];
          if (clinics.isEmpty) return _error(NearbyError('No clinics found nearby.', 'empty'));
          return _list(clinics);
        },
      ),
    );
  }

  Widget _list(List<Clinic> clinics) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        itemCount: clinics.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _card(clinics[i]),
      );

  Widget _card(Clinic c) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => NearbyDoctors.directionsTo(c),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (c.isDermatology ? Themes.primary : Themes.mint).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(c.isDermatology ? Icons.medical_services_outlined : Icons.local_hospital_outlined,
                    color: c.isDermatology ? Themes.primary : Themes.mint),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 3),
                  Row(children: [
                    _chip(c.kind, c.isDermatology),
                    const SizedBox(width: 8),
                    const Icon(Icons.place_outlined, size: 14, color: Themes.muted),
                    const SizedBox(width: 2),
                    Text(c.distanceLabel,
                        style: const TextStyle(color: Themes.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                  if (c.address != null) ...[
                    const SizedBox(height: 4),
                    Text(c.address!, style: const TextStyle(color: Themes.muted, fontSize: 12.5)),
                  ],
                ]),
              ),
              const SizedBox(width: 6),
              Column(children: const [
                Icon(Icons.directions_rounded, color: Themes.primary),
                SizedBox(height: 2),
                Text('Directions', style: TextStyle(color: Themes.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ),
      );

  Widget _chip(String label, bool derma) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (derma ? Themes.primary : Themes.muted).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: derma ? Themes.primary : Themes.muted)),
      );

  Widget _error(Object? error) {
    final ne = error is NearbyError ? error : NearbyError('Something went wrong.', 'network');
    final (icon, canRetry) = switch (ne.kind) {
      'permission' => (Icons.location_disabled_rounded, true),
      'service_off' => (Icons.location_off_rounded, true),
      'empty' => (Icons.search_off_rounded, true),
      _ => (Icons.wifi_off_rounded, true),
    };
    return _Centered(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Themes.muted),
          const SizedBox(height: 14),
          Text(ne.message, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 20),
          if (canRetry)
            OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => openNearbyDermatologists(context),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open in Google Maps'),
          ),
        ]),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
