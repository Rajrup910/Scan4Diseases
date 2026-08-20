import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// A clinic/doctor result from OpenStreetMap, with on-device distance from the user.
class Clinic {
  Clinic({
    required this.name,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    this.address,
    this.phone,
    this.openingHours,
    this.website,
    this.rating,
    this.isDermatology = false,
  });

  final String name;
  final String kind; // "Dermatology", "Hospital", "Clinic", "Doctors"…
  final double lat;
  final double lng;
  final double distanceKm;
  final String? address;
  final String? phone;
  final String? openingHours;
  final String? website;
  final double? rating; // OSM 'stars' if tagged — usually absent for clinics.
  final bool isDermatology;

  String get distanceLabel =>
      distanceKm < 1 ? '${(distanceKm * 1000).round()} m' : '${distanceKm.toStringAsFixed(1)} km';

  bool get hasRating => rating != null;

  /// A rough "how far" descriptor for a walking/driving decision at a glance.
  String get proximityLabel {
    if (distanceKm < 1) return 'Very close';
    if (distanceKm < 3) return 'Nearby';
    if (distanceKm < 10) return 'A short drive';
    return 'Further out';
  }
}

/// A user-friendly failure with a stable [kind] the UI can branch on.
class NearbyError implements Exception {
  NearbyError(this.message, this.kind);
  final String message;
  final String kind; // 'service_off' | 'permission' | 'network' | 'empty'
  @override
  String toString() => message;
}

/// Finds nearby doctors/clinics via OpenStreetMap's Nominatim search (no API key, no cost).
///
/// Nominatim is used instead of the Overpass API because Overpass's public mirrors are
/// frequently overloaded and time out (10–30s+), which surfaced to users as a constant
/// "could not reach the map service" error. Nominatim answers a bounded text search in
/// well under a second. Dermatology-named places are ranked first, then everything by
/// distance. Coverage is OSM's — thin in rural areas — so the term search widens
/// (dermatologist → skin clinic → clinic → hospital) and the box grows before giving up,
/// and the UI always offers a Google Maps fallback.
class NearbyDoctors {
  static const _endpoint = 'https://nominatim.openstreetmap.org/search';

  /// Nominatim's usage policy requires a descriptive User-Agent identifying the app.
  static const _userAgent = 'Scan4Disease/1.0 (dermatology screening MP online)';

  /// Dermatology first; broaden only if too few results are found.
  static const _terms = ['dermatologist', 'skin clinic', 'clinic', 'hospital'];

  /// Half-size of the search box in degrees of latitude (~0.27° ≈ 30 km, ~0.6° ≈ 65 km).
  static const _boxHalfDeg = [0.27, 0.6];

  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw NearbyError('Location is turned off. Turn it on and try again.', 'service_off');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw NearbyError(
          'Location permission is needed to find clinics near you.', 'permission');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }

  static Future<List<Clinic>> search({int minResults = 8, int limit = 30}) async {
    final pos = await currentPosition();
    final out = <Clinic>[];
    final seen = <String>{};
    var anyRequestSucceeded = false;

    for (final half in _boxHalfDeg) {
      for (final term in _terms) {
        List<dynamic> items;
        try {
          items = await _nominatim(term, pos.latitude, pos.longitude, half);
          anyRequestSucceeded = true;
        } catch (_) {
          continue; // Try the next term/box; only a total wipe-out is a network error.
        }
        for (final c in _parse(items, pos.latitude, pos.longitude)) {
          // Dedupe places that show up under several search terms.
          final key = '${c.lat.toStringAsFixed(4)},${c.lng.toStringAsFixed(4)}';
          if (seen.add(key)) out.add(c);
        }
        if (out.length >= minResults) break;
      }
      if (out.length >= minResults) break;
    }

    if (!anyRequestSucceeded) {
      throw NearbyError('Could not reach the map service. Check your connection.', 'network');
    }
    if (out.isEmpty) {
      throw NearbyError('No clinics were listed near you on the map data.', 'empty');
    }
    out.sort((a, b) {
      if (a.isDermatology != b.isDermatology) return a.isDermatology ? -1 : 1;
      return a.distanceKm.compareTo(b.distanceKm);
    });
    return out.take(limit).toList();
  }

  /// One bounded Nominatim text search around ([lat], [lng]). Throws on transport failure.
  static Future<List<dynamic>> _nominatim(
      String term, double lat, double lng, double halfDeg) async {
    // Convert the latitude half-size into a longitude half-size (degrees shrink towards the poles).
    final lonHalf = halfDeg / cos(_rad(lat)).abs().clamp(0.2, 1.0);
    final west = lng - lonHalf, east = lng + lonHalf;
    final north = lat + halfDeg, south = lat - halfDeg;

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': term,
      'format': 'jsonv2',
      'limit': '25',
      'addressdetails': '1',
      'extratags': '1',
      'viewbox': '$west,$north,$east,$south',
      'bounded': '1',
    });

    final res = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 200 && res.body.trimLeft().startsWith('[')) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    throw NearbyError('Map service returned ${res.statusCode}.', 'network');
  }

  static List<Clinic> _parse(List<dynamic> items, double userLat, double userLng) {
    final out = <Clinic>[];
    for (final e in items) {
      if (e is! Map) continue;
      final tags = ((e['extratags'] as Map?) ?? const {}).cast<String, dynamic>();
      final addr = ((e['address'] as Map?) ?? const {}).cast<String, dynamic>();

      final name = (e['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final lat = double.tryParse('${e['lat']}');
      final lng = double.tryParse('${e['lon']}');
      if (lat == null || lng == null) continue;

      final type = '${e['type'] ?? ''}'.toLowerCase();
      final lname = name.toLowerCase();
      final isDerma = lname.contains('derma') || lname.contains('skin') || type.contains('derma');

      out.add(Clinic(
        name: name,
        kind: _kind(type, isDerma),
        lat: lat,
        lng: lng,
        distanceKm: _haversineKm(userLat, userLng, lat, lng),
        address: _address(addr),
        phone: (tags['phone'] ?? tags['contact:phone'] ?? tags['mobile'])?.toString(),
        openingHours: (tags['opening_hours'])?.toString(),
        website: (tags['website'] ?? tags['contact:website'])?.toString(),
        rating: double.tryParse((tags['stars'] ?? '').toString()),
        isDermatology: isDerma,
      ));
    }
    return out;
  }

  static String _kind(String type, bool isDerma) {
    if (isDerma) return 'Dermatology';
    return switch (type) {
      'hospital' => 'Hospital',
      'doctors' => 'Doctor',
      'clinic' => 'Clinic',
      'pharmacy' => 'Pharmacy',
      _ => 'Clinic',
    };
  }

  static String? _address(Map<String, dynamic> tags) {
    final street = [tags['house_number'], tags['road']]
        .where((x) => x != null && x.toString().trim().isNotEmpty)
        .map((x) => x.toString())
        .join(' ');
    final parts = [
      if (street.isNotEmpty) street,
      tags['suburb'] ?? tags['neighbourhood'],
      tags['city'] ?? tags['town'] ?? tags['village'] ?? tags['city_district'],
    ].where((x) => x != null && x.toString().trim().isNotEmpty).map((x) => x.toString());
    return parts.isEmpty ? null : parts.join(', ');
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double d) => d * pi / 180;

  /// Open turn-by-turn directions from the user's location to [c].
  static Future<void> directionsTo(Clinic c) async {
    final candidates = <Uri>[
      Uri.parse('google.navigation:q=${c.lat},${c.lng}'),
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}&travelmode=driving'),
      Uri.parse('geo:${c.lat},${c.lng}?q=${c.lat},${c.lng}(${Uri.encodeComponent(c.name)})'),
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {/* next */}
    }
  }
}
