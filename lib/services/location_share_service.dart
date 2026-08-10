import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'network_service.dart';

/// Keeps uploading this device's GPS while the app process is alive
/// (including when the user switches to another app).
///
/// On Android this uses a foreground-service notification so the OS does not
/// kill location updates in the background.
class LocationShareService {
  LocationShareService(this._network);

  final NetworkService _network;

  StreamSubscription<Position>? _positionSub;
  Timer? _uploadTimer;
  Position? lastPosition;
  String? statusMessage;
  bool _starting = false;
  DateTime? _lastUploadAt;
  Position? _lastUploadedPosition;

  static const _uploadInterval = Duration(seconds: 30);
  static const _minUploadDistanceMeters = 20.0;

  bool get isRunning => _positionSub != null;

  LocationSettings get _settings {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 15),
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
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
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

  Future<void> start({void Function(Position position)? onPosition}) async {
    if (_starting || isRunning) return;
    _starting = true;
    try {
      final ok = await ensurePermission();
      if (!ok) return;

      _positionSub = Geolocator.getPositionStream(locationSettings: _settings).listen(
        (position) {
          final shouldForce = _shouldUploadEarly(position);
          lastPosition = position;
          statusMessage = null;
          onPosition?.call(position);
          unawaited(_maybeUpload(force: shouldForce));
        },
        onError: (_) {
          statusMessage = 'Could not read GPS position.';
        },
      );

      _uploadTimer?.cancel();
      _uploadTimer = Timer.periodic(_uploadInterval, (_) {
        unawaited(_maybeUpload(force: true));
      });

      try {
        final quick = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        lastPosition = quick;
        onPosition?.call(quick);
        await _maybeUpload(force: true);
      } catch (_) {}
    } finally {
      _starting = false;
    }
  }

  bool _shouldUploadEarly(Position next) {
    final prev = _lastUploadedPosition;
    if (prev == null) return true;
    final d = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );
    return d >= _minUploadDistanceMeters;
  }

  Future<void> _maybeUpload({required bool force}) async {
    final position = lastPosition;
    if (position == null) return;

    final now = DateTime.now();
    if (!force && _lastUploadAt != null) {
      final elapsed = now.difference(_lastUploadAt!);
      if (elapsed < _uploadInterval) return;
    }

    try {
      await _network.updateLocation(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
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
}
