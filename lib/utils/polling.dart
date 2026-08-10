import 'dart:math' as math;

/// Haversine distance in meters between two GPS points.
double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadius = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _toRad(double deg) => deg * math.pi / 180;

/// Polling interval based on distance (Medicine Compass).
Duration pollingIntervalForDistance(double? meters) {
  if (meters == null) return const Duration(seconds: 5);
  if (meters > 1000) return const Duration(seconds: 30);
  if (meters >= 100) return const Duration(seconds: 5);
  return const Duration(seconds: 2);
}
