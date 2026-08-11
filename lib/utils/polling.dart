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
double _toDeg(double rad) => rad * 180 / math.pi;

/// Destination point after traveling [distanceMeters] along [bearingDegrees].
({double lat, double lng}) destinationPoint({
  required double lat,
  required double lng,
  required double bearingDegrees,
  required double distanceMeters,
}) {
  const earthRadius = 6371000.0;
  final brng = _toRad(bearingDegrees);
  final angDist = distanceMeters / earthRadius;
  final lat1 = _toRad(lat);
  final lon1 = _toRad(lng);

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angDist) +
        math.cos(lat1) * math.sin(angDist) * math.cos(brng),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(brng) * math.sin(angDist) * math.cos(lat1),
        math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
      );

  return (lat: _toDeg(lat2), lng: _toDeg(lon2));
}

/// Extrapolate a peer fix using last known speed/heading (dead reckoning).
/// Caps age so stale motion does not invent large errors.
({double lat, double lng})? extrapolatePeerPosition({
  required double lat,
  required double lng,
  double? speedMps,
  double? headingDegrees,
  required DateTime? fixTime,
  DateTime? now,
  Duration maxAge = const Duration(seconds: 45),
}) {
  if (speedMps == null || headingDegrees == null || fixTime == null) {
    return null;
  }
  if (!speedMps.isFinite || speedMps < 0.4) return null;
  if (!headingDegrees.isFinite || headingDegrees < 0) return null;

  final age = (now ?? DateTime.now()).difference(fixTime);
  if (age.isNegative || age > maxAge) return null;

  final traveled = speedMps * age.inMilliseconds / 1000.0;
  if (traveled < 1) return null;
  // Hard cap: never invent more than ~120 m of coasting.
  final capped = traveled.clamp(0, 120).toDouble();
  return destinationPoint(
    lat: lat,
    lng: lng,
    bearingDegrees: headingDegrees,
    distanceMeters: capped,
  );
}

/// How often the compass should poll the peer over the network.
///
/// Tuned for cellular: denser when close (navigation matters), sparse when
/// far (map-scale error dominates anyway). Peer speed shortens the interval
/// so a moving friend does not appear "stuck".
Duration pollingIntervalForDistance(
  double? meters, {
  double? peerSpeedMps,
  DateTime? peerFixTime,
}) {
  Duration base;
  if (meters == null) {
    base = const Duration(seconds: 6);
  } else if (meters > 3000) {
    base = const Duration(seconds: 45);
  } else if (meters > 1000) {
    base = const Duration(seconds: 25);
  } else if (meters > 300) {
    base = const Duration(seconds: 10);
  } else if (meters > 80) {
    base = const Duration(seconds: 5);
  } else {
    base = const Duration(seconds: 3);
  }

  final speed = peerSpeedMps ?? 0;
  if (speed >= 8) {
    // Driving / cycling — refresh sooner.
    base = Duration(milliseconds: (base.inMilliseconds * 0.55).round());
  } else if (speed >= 1.5) {
    base = Duration(milliseconds: (base.inMilliseconds * 0.75).round());
  } else if (speed < 0.3 && peerFixTime != null) {
    // Peer looks stationary — stretch polling to save data.
    final age = DateTime.now().difference(peerFixTime);
    if (age > const Duration(seconds: 20)) {
      base = Duration(milliseconds: (base.inMilliseconds * 1.4).round());
    }
  }

  final ms = base.inMilliseconds.clamp(2500, 60000);
  return Duration(milliseconds: ms);
}

/// Adaptive upload heartbeat for our own GPS (cellular-friendly).
Duration uploadHeartbeatForMotion({
  required double speedMps,
  required bool priorityMode,
}) {
  if (priorityMode) {
    if (speedMps >= 5) return const Duration(seconds: 5);
    if (speedMps >= 1) return const Duration(seconds: 8);
    return const Duration(seconds: 12);
  }
  if (speedMps >= 8) return const Duration(seconds: 10);
  if (speedMps >= 1.2) return const Duration(seconds: 20);
  return const Duration(seconds: 55);
}

/// Minimum movement before forcing an early upload.
double uploadDistanceThresholdMeters({
  required double speedMps,
  required bool priorityMode,
}) {
  if (priorityMode) {
    if (speedMps >= 5) return 12;
    if (speedMps >= 1) return 8;
    return 10;
  }
  if (speedMps >= 8) return 30;
  if (speedMps >= 1.2) return 18;
  return 40;
}
