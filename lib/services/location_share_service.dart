import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/polling.dart';
import 'network_service.dart';

/// Keeps uploading this device's GPS while the app process is alive
/// (including when the user switches to another app).
///
/// Upload cadence is motion-adaptive and quality-gated so cellular usage
/// stays low while fixes stay useful for paired navigation.
class LocationShareService {
  LocationShareService(this._network);

  final NetworkService _network;

  StreamSubscription<Position>? _positionSub;
  Timer? _uploadTimer;
  Position? lastPosition;
  Position? _bestRecentPosition;
  String? statusMessage;
  bool _starting = false;
  bool _priorityMode = false;
  DateTime? _lastUploadAt;
  Position? _lastUploadedPosition;
  void Function(Position position)? _onPosition;

  /// Reject noisy fixes unless nothing better is available.
  static const _maxPreferredAccuracyM = 40.0;
  static const _maxAcceptableAccuracyM = 85.0;

  bool get isRunning => _positionSub != null;
  bool get priorityMode => _priorityMode;

  LocationSettings get _settings {
    final accuracy = _priorityMode
        ? LocationAccuracy.bestForNavigation
        : LocationAccuracy.high;
    final distanceFilter = _priorityMode ? 5 : 12;
    final interval = _priorityMode
        ? const Duration(seconds: 3)
        : const Duration(seconds: 10);

    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Medicine Compass',
          notificationText: 'Sharing your location with paired people',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      statusMessage = 'Turn on GPS location in your phone settings.';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      statusMessage = 'Location permission is required to share your position.';
      return false;
    }
    statusMessage = null;
    return true;
  }

  /// Compass open → denser GPS + faster uploads; list/background → thriftier.
  Future<void> setPriorityMode(bool enabled) async {
    if (_priorityMode == enabled) return;
    _priorityMode = enabled;
    if (!isRunning) return;

    final callback = _onPosition;
    await _positionSub?.cancel();
    _positionSub = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    // Allow start() again with new settings.
    await start(onPosition: callback);
  }

  Future<void> start({void Function(Position position)? onPosition}) async {
    if (onPosition != null) _onPosition = onPosition;
    if (_starting || isRunning) return;
    _starting = true;
    try {
      final ok = await ensurePermission();
      if (!ok) return;

      _positionSub =
          Geolocator.getPositionStream(locationSettings: _settings).listen(
        (position) {
          _handleFix(position);
        },
        onError: (_) {
          statusMessage = 'Could not read GPS position.';
        },
      );

      _armUploadTimer();

      try {
        final quick = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: _priorityMode
                ? LocationAccuracy.bestForNavigation
                : LocationAccuracy.high,
          ),
        );
        _handleFix(quick, forceUpload: true);
      } catch (_) {}
    } finally {
      _starting = false;
    }
  }

  void _handleFix(Position position, {bool forceUpload = false}) {
    if (!_acceptFix(position)) {
      // Still surface last good fix to UI; skip network if garbage.
      if (lastPosition != null) {
        _onPosition?.call(lastPosition!);
      }
      return;
    }

    lastPosition = position;
    _bestRecentPosition = position;
    statusMessage = null;
    _onPosition?.call(position);

    final shouldForce = forceUpload || _shouldUploadEarly(position);
    unawaited(_maybeUpload(force: shouldForce));
    _armUploadTimer();
  }

  bool _acceptFix(Position next) {
    final acc = next.accuracy;
    if (!acc.isFinite || acc <= 0) return true;
    if (acc <= _maxPreferredAccuracyM) return true;

    final prev = _bestRecentPosition ?? lastPosition;
    if (prev == null) return acc <= _maxAcceptableAccuracyM;

    // Prefer a clearly better fix even if still coarse.
    if (acc + 8 < prev.accuracy) return true;

    // Accept a coarse fix if the previous good one is old (>25s).
    final age = DateTime.now().difference(prev.timestamp);
    if (age > const Duration(seconds: 25) && acc <= _maxAcceptableAccuracyM) {
      return true;
    }
    return false;
  }

  void _armUploadTimer() {
    _uploadTimer?.cancel();
    final speed = _safeSpeed(lastPosition);
    final wait = uploadHeartbeatForMotion(
      speedMps: speed,
      priorityMode: _priorityMode,
    );
    _uploadTimer = Timer(wait, () {
      unawaited(_maybeUpload(force: true));
      _armUploadTimer();
    });
  }

  bool _shouldUploadEarly(Position next) {
    final prev = _lastUploadedPosition;
    if (prev == null) return true;

    final speed = _safeSpeed(next);
    final threshold = uploadDistanceThresholdMeters(
      speedMps: speed,
      priorityMode: _priorityMode,
    );
    final d = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );
    if (d >= threshold) return true;

    // Better accuracy while nearly still is worth a cheap update.
    if (next.accuracy.isFinite &&
        prev.accuracy.isFinite &&
        next.accuracy + 10 < prev.accuracy &&
        d < 15) {
      return true;
    }
    return false;
  }

  Future<void> _maybeUpload({required bool force}) async {
    final position = lastPosition;
    if (position == null) return;

    final now = DateTime.now();
    final speed = _safeSpeed(position);
    final minGap = uploadHeartbeatForMotion(
      speedMps: speed,
      priorityMode: _priorityMode,
    );

    if (!force && _lastUploadAt != null) {
      if (now.difference(_lastUploadAt!) < minGap) return;
    }

    // Heartbeat while stationary: skip network if nothing meaningful changed.
    if (force && _lastUploadedPosition != null && _lastUploadAt != null) {
      final prev = _lastUploadedPosition!;
      final d = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        position.latitude,
        position.longitude,
      );
      final age = now.difference(_lastUploadAt!);
      final still = speed < 0.4 && d < 8;
      if (still && !priorityMode && age < const Duration(seconds: 90)) {
        return;
      }
      if (still && priorityMode && age < const Duration(seconds: 20)) {
        return;
      }
    }

    try {
      await _network.updateLocation(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy.isFinite ? position.accuracy : null,
        speed: _nullableSpeed(position),
        heading: _nullableHeading(position),
        timestamp: position.timestamp,
      );
      _lastUploadAt = now;
      _lastUploadedPosition = position;
    } on NetworkException {
      // Keep last known locally; next tick retries.
    } catch (_) {}
  }

  Future<void> uploadNow() => _maybeUpload(force: true);

  Future<void> stop() async {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
  }

  static double _safeSpeed(Position? p) {
    if (p == null) return 0;
    final s = p.speed;
    if (!s.isFinite || s < 0) return 0;
    return s;
  }

  static double? _nullableSpeed(Position p) {
    final s = p.speed;
    if (!s.isFinite || s < 0) return null;
    return double.parse(s.toStringAsFixed(1));
  }

  static double? _nullableHeading(Position p) {
    final h = p.heading;
    if (!h.isFinite || h < 0) return null;
    // Normalize 0..360
    final norm = h % 360;
    return double.parse(norm.toStringAsFixed(1));
  }
}
