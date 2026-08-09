import 'dart:math' as math;

/// Haversine — dystans w metrach między dwoma punktami GPS.
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

/// Interwał odświeżania pozycji w zależności od dystansu.
Duration pollingIntervalForDistance(double? meters) {
  if (meters == null) return const Duration(seconds: 10);
  if (meters > 1000) return const Duration(seconds: 60);
  if (meters >= 100) return const Duration(seconds: 10);
  return const Duration(seconds: 5);
}
