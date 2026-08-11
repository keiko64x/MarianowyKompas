import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'models/peer.dart';
import 'models/user_profile.dart';
import 'services/location_share_service.dart';
import 'services/network_service.dart';
import 'services/profile_store.dart';
import 'utils/polling.dart';
import 'utils/spirit_names.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double arrivalRadiusMeters = 5.0;
const Duration _kMenuAnimDuration = Duration(milliseconds: 400);
const double _kWelcomeTitleHeight = 66;
const double _kHeaderTitleHeight = 89;
const double _kSquareButtonSize = 72;
const Duration _kPendingPollInterval = Duration(seconds: 20);

String _formatDistanceValue(double? meters) {
  if (meters == null) return '...';
  if (meters <= 1000) return '${meters.round()}';
  return (meters / 1000).toStringAsFixed(2);
}

String _formatDistanceUnit(double? meters) {
  if (meters == null) return '';
  return meters <= 1000 ? 'meters' : 'km';
}

String _formatClock(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

enum AppThemeMode { dark, light }

class AppPalette {
  const AppPalette(this.mode);

  final AppThemeMode mode;

  bool get isDark => mode == AppThemeMode.dark;

  Color get background => isDark ? const Color(0xFF1A2E1F) : const Color(0xFFF4F0E6);
  Color get containerBackground => isDark ? const Color(0xFF243528) : Colors.white;
  Color get surface => isDark ? const Color(0xFF2E4033) : const Color(0xFFEBE4D6);
  Color get surfaceBorder => isDark ? const Color(0xFF3D5442) : const Color(0xFFC4A882);
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF2A1F14);
  Color get textSecondary => isDark ? const Color(0xFFC9D5C4) : const Color(0xFF5C4A3A);
  Color get accent => isDark ? const Color(0xFF8FAE8B) : const Color(0xFF2F5D3A);
  Color get arrow => isDark ? const Color(0xFF8FAE8B) : const Color(0xFF2F5D3A);
  Color get buttonBackground => isDark ? const Color(0xFF3A4F3C) : const Color(0xFFE0D5C2);
  Color get buttonForeground => isDark ? Colors.white : const Color(0xFF2A1F14);
  Color get gpsBar => isDark ? const Color(0xFF15251A) : const Color(0xFFE8DFD0);
  Color get success => Colors.green.shade500;

  ThemeData toThemeData() {
    return ThemeData(
      scaffoldBackgroundColor: background,
      brightness: isDark ? Brightness.dark : Brightness.light,
      textTheme: TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 16, color: textSecondary),
        bodyLarge: TextStyle(fontSize: 18, color: textSecondary),
      ),
    );
  }
}

class AppSettings extends ChangeNotifier {
  AppThemeMode _theme = AppThemeMode.dark;
  final ProfileStore _store = ProfileStore();

  AppThemeMode get theme => _theme;
  AppPalette get palette => AppPalette(_theme);

  Future<void> load() async {
    final value = await _store.loadTheme();
    _theme = value == 'light' ? AppThemeMode.light : AppThemeMode.dark;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode mode) async {
    _theme = mode;
    notifyListeners();
    await _store.saveTheme(mode == AppThemeMode.light ? 'light' : 'dark');
  }
}

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(MedicineCompassApp(settings: settings));
}

class MedicineCompassApp extends StatelessWidget {
  const MedicineCompassApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Medicine Compass',
          debugShowCheckedModeBanner: false,
          theme: settings.palette.toThemeData(),
          home: _AppRoot(settings: settings),
        );
      },
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.settings});

  final AppSettings settings;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool? _showWelcome;

  @override
  void initState() {
    super.initState();
    _loadWelcomePref();
  }

  Future<void> _loadWelcomePref() async {
    final skip = await ProfileStore().loadSkipWelcome();
    if (!mounted) return;
    setState(() => _showWelcome = !skip);
  }

  Future<void> _completeWelcome(bool dontShowAgain) async {
    if (dontShowAgain) {
      await ProfileStore().setSkipWelcome(true);
    }
    if (!mounted) return;
    setState(() => _showWelcome = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showWelcome == null) {
      return Scaffold(
        backgroundColor: widget.settings.palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_showWelcome!) {
      return _WelcomeScreen(
        settings: widget.settings,
        onContinue: _completeWelcome,
      );
    }
    return MainScreen(settings: widget.settings);
  }
}

class _WelcomeScreen extends StatefulWidget {
  const _WelcomeScreen({required this.settings, required this.onContinue});

  final AppSettings settings;
  final ValueChanged<bool> onContinue;

  @override
  State<_WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<_WelcomeScreen> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.settings.palette;
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: palette.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  SizedBox(
                    height: _kWelcomeTitleHeight,
                    child: Center(
                      child: Text(
                        'Medicine Compass',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: palette.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Medicine Compass is a real-time people radar. '
                    'Pair with someone using a QR code, then select them from the list '
                    'to navigate with an arrow to their current GPS position.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(flex: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: _kSquareButtonSize,
                          child: _SquareMenuButton(
                            palette: palette,
                            label: 'Got it',
                            icon: Icons.check,
                            onPressed: () => widget.onContinue(_dontShowAgain),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _dontShowAgain,
                                onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                                activeColor: palette.accent,
                              ),
                              Expanded(
                                child: Text(
                                  "Don't show again",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Screen modes
// ---------------------------------------------------------------------------

enum _ScreenMode { people, add, editList, editItem, info, compass }

enum _MenuButton { list, add, edit, info }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final ProfileStore _store = ProfileStore();
  final NetworkService _network = NetworkService();
  late final LocationShareService _locationShare = LocationShareService(_network);

  _ScreenMode _mode = _ScreenMode.people;
  UserProfile? _profile;
  List<Peer> _peers = [];
  Peer? _compassPeer;
  Peer? _editingPeer;

  Position? _currentPosition;
  Position? _lastKnownPosition;
  String? _gpsStatusMessage;
  double? _deviceHeading;
  String? _compassError;
  bool _compassPermissionGranted = false;
  bool _gpsSearchTimeout = false;
  bool _bootstrapping = true;
  String? _networkBanner;
  bool _usingCachedPeerLocation = false;
  DateTime? _peerLocationFetchedAt;
  PeerLocation? _livePeerLocation;

  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _gpsSearchTimer;
  Timer? _pollTimer;
  Timer? _pendingTimer;
  Timer? _extrapolationTick;
  bool _handlingPending = false;
  final Set<String> _seenRequestIds = {};

  AppPalette get _palette => widget.settings.palette;
  bool get _isCompassActive => _mode == _ScreenMode.compass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCompassTracking();
    unawaited(_locationShare.setPriorityMode(false));
    unawaited(_locationShare.stop());
    _pendingTimer?.cancel();
    _network.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_ensureLocationSharing());
        if (_isCompassActive && _compassPeer != null) {
          unawaited(_startCompassSession(_compassPeer!));
        } else {
          _startPendingWatcher();
          unawaited(_refreshPeers());
        }
      case AppLifecycleState.inactive:
        // Ignore — fires for transient system UI.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Keep sharing GPS in background; throttle to non-priority cadence
        // and pause compass/peer polling to save cellular data.
        _stopCompassTracking(keepCompassMode: true);
        unawaited(_locationShare.setPriorityMode(false));
        _pendingTimer?.cancel();
      case AppLifecycleState.detached:
        _stopCompassTracking();
        unawaited(_locationShare.stop());
        _pendingTimer?.cancel();
    }
  }

  Future<void> _bootstrap() async {
    final cachedPeers = await _store.loadPeersCache();
    var profile = await _store.loadProfile();

    if (profile == null) {
      try {
        final deviceName = await _defaultDeviceName();
        profile = await _network.registerProfile(deviceName);
        await _store.saveProfile(profile);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _bootstrapping = false;
          _networkBanner = e is NetworkException
              ? e.message
              : 'Could not register profile. Check your network.';
        });
        return;
      }
    }

    _network.setProfile(profile);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _peers = cachedPeers;
      _bootstrapping = false;
    });

    await _refreshPeers();
    _startPendingWatcher();
    await _ensureLocationSharing();
  }

  Future<void> _ensureLocationSharing() async {
    await _locationShare.start(
      onPosition: (position) {
        if (!mounted) return;
        setState(() {
          _currentPosition = position;
          _lastKnownPosition = position;
          _gpsStatusMessage = _locationShare.statusMessage;
          if (_isCompassActive) {
            _gpsSearchTimeout = false;
          }
        });
        if (_isCompassActive) _cancelGpsSearchTimer();
      },
    );
    if (!mounted) return;
    if (_locationShare.lastPosition != null) {
      setState(() {
        _currentPosition = _locationShare.lastPosition;
        _lastKnownPosition = _locationShare.lastPosition;
        _gpsStatusMessage = _locationShare.statusMessage;
      });
    } else if (_locationShare.statusMessage != null) {
      setState(() => _gpsStatusMessage = _locationShare.statusMessage);
    }
  }

  Future<String> _defaultDeviceName() async {
    return randomSpiritProfileName();
  }

  Future<void> _refreshPeers() async {
    if (_profile == null) return;
    try {
      final peers = await _network.fetchPeers();
      await _store.savePeersCache(peers);
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _networkBanner = null;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _networkBanner = e.offline
            ? 'No signal — showing last known list.'
            : e.message;
      });
    }
  }

  void _startPendingWatcher() {
    _pendingTimer?.cancel();
    _pendingTimer = Timer.periodic(_kPendingPollInterval, (_) {
      if (!_isCompassActive) {
        _checkPendingPairs();
      }
    });
    _checkPendingPairs();
  }

  Future<void> _checkPendingPairs() async {
    if (_profile == null || _handlingPending || !mounted) return;
    try {
      final pending = await _network.fetchPendingPairs();
      for (final request in pending) {
        if (_seenRequestIds.contains(request.id)) continue;
        _seenRequestIds.add(request.id);
        _handlingPending = true;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: _palette.containerBackground,
            title: Text('Pairing request', style: TextStyle(color: _palette.textPrimary)),
            content: Text(
              '${request.fromName ?? 'Someone'} wants to pair with you. '
              'After accepting, you will both appear on each other\'s list.',
              style: TextStyle(color: _palette.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Decline', style: TextStyle(color: Colors.red.shade400)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Accept', style: TextStyle(color: _palette.accent)),
              ),
            ],
          ),
        );
        try {
          if (accepted == true) {
            await _network.acceptPair(request.id);
          } else {
            await _network.rejectPair(request.id);
          }
          await _refreshPeers();
        } on NetworkException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        } finally {
          _handlingPending = false;
        }
      }
    } catch (_) {
      // silent — pending polling must not block UI
    }
  }

  void _goToDefault() {
    _stopCompassTracking();
    setState(() {
      _mode = _ScreenMode.people;
      _compassPeer = null;
      _editingPeer = null;
      _compassError = null;
      _gpsSearchTimeout = false;
      _usingCachedPeerLocation = false;
      _livePeerLocation = null;
      _peerLocationFetchedAt = null;
    });
    _startPendingWatcher();
    unawaited(_ensureLocationSharing());
    unawaited(_refreshPeers());
  }

  _MenuButton? get _activeMenuButton {
    switch (_mode) {
      case _ScreenMode.people:
        return _MenuButton.list;
      case _ScreenMode.add:
        return _MenuButton.add;
      case _ScreenMode.editList:
      case _ScreenMode.editItem:
        return _MenuButton.edit;
      case _ScreenMode.info:
        return _MenuButton.info;
      default:
        return null;
    }
  }

  // --- Location share / Compass session ---

  /// Stops peer polling + compass sensors. Does NOT stop background location share.
  void _stopCompassTracking({bool keepCompassMode = false}) {
    _cancelGpsSearchTimer();
    _pollTimer?.cancel();
    _pollTimer = null;
    _extrapolationTick?.cancel();
    _extrapolationTick = null;
    _compassSubscription?.cancel();
    _compassSubscription = null;
    if (!keepCompassMode) {
      _compassPermissionGranted = false;
      _deviceHeading = null;
      unawaited(_locationShare.setPriorityMode(false));
    }
  }

  Future<void> _openCompass(Peer peer) async {
    _pendingTimer?.cancel();
    setState(() {
      _mode = _ScreenMode.compass;
      _compassPeer = peer;
      _compassError = null;
      _gpsSearchTimeout = false;
      _deviceHeading = null;
      _usingCachedPeerLocation = false;
      _livePeerLocation = peer.cachedLatitude != null && peer.cachedLongitude != null
          ? PeerLocation(
              userId: peer.userId,
              latitude: peer.cachedLatitude!,
              longitude: peer.cachedLongitude!,
              timestamp: peer.cachedAt,
              fetchedAt: peer.cachedAt,
              lastActivityLabel: peer.lastActivityLabel,
            )
          : null;
      _peerLocationFetchedAt = peer.cachedAt;
    });
    await _startCompassSession(peer);
  }

  Future<void> _startCompassSession(Peer peer) async {
    _stopCompassTracking(keepCompassMode: true);
    await _locationShare.setPriorityMode(true);
    await _ensureLocationSharing();
    _startGpsSearchTimer();
    _startExtrapolationTick();

    final ok = await _locationShare.ensurePermission();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _compassError =
            _locationShare.statusMessage ?? 'Location permission required.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _compassPermissionGranted = true;
      _compassError = null;
      _currentPosition = _locationShare.lastPosition ?? _currentPosition;
      _lastKnownPosition = _currentPosition ?? _lastKnownPosition;
      _gpsStatusMessage = _locationShare.statusMessage;
    });

    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (!mounted || !_isCompassActive) return;
        final heading = event.heading;
        if (heading != null) setState(() => _deviceHeading = heading);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _compassError = 'Could not read compass.');
      },
    );

    // One fresh self-upload when opening compass; afterwards the adaptive
    // share service handles uploads without doubling every peer poll.
    await _locationShare.uploadNow();
    await _pollOnce(peer);
    _scheduleNextPoll(peer);
  }

  void _startExtrapolationTick() {
    _extrapolationTick?.cancel();
    // Cheap local UI refresh so the arrow coasts between network polls.
    _extrapolationTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isCompassActive) return;
      final peer = _livePeerLocation;
      if (peer == null) return;
      if ((peer.speed ?? 0) < 0.4) return;
      setState(() {});
    });
  }

  void _scheduleNextPoll(Peer peer) {
    _pollTimer?.cancel();
    if (!_isCompassActive) return;
    final distance = _distanceToTarget();
    final wait = pollingIntervalForDistance(
      distance,
      peerSpeedMps: _livePeerLocation?.speed,
      peerFixTime: _livePeerLocation?.timestamp,
    );
    _pollTimer = Timer(wait, () async {
      if (!_isCompassActive || _compassPeer?.userId != peer.userId) return;
      await _pollOnce(peer);
      _scheduleNextPoll(peer);
    });
  }

  Future<void> _pollOnce(Peer peer) async {
    try {
      final loc = await _network.fetchLocation(
        peer.userId,
        ifNoneMatch: _livePeerLocation?.etag ??
            _livePeerLocation?.timestamp?.toIso8601String(),
      );
      if (!mounted || _compassPeer?.userId != peer.userId) return;

      // 304 Not Modified — peer fix unchanged; keep local state, save data.
      if (loc == null) {
        setState(() {
          _usingCachedPeerLocation = false;
          _networkBanner = null;
        });
        return;
      }

      final updatedPeers = _peers.map((p) {
        if (p.userId != peer.userId) return p;
        return p.copyWith(
          cachedLatitude: loc.latitude,
          cachedLongitude: loc.longitude,
          cachedAt: loc.timestamp ?? loc.fetchedAt,
          lastSeenAt: loc.timestamp?.toIso8601String(),
          lastActivityLabel: loc.lastActivityLabel ?? p.lastActivityLabel,
          hasLocation: true,
        );
      }).toList();
      await _store.savePeersCache(updatedPeers);
      setState(() {
        _peers = updatedPeers;
        _livePeerLocation = loc;
        _peerLocationFetchedAt = loc.fetchedAt ?? DateTime.now();
        _usingCachedPeerLocation = false;
        _networkBanner = null;
        _compassPeer = updatedPeers.firstWhere(
          (p) => p.userId == peer.userId,
          orElse: () => peer,
        );
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      if (_livePeerLocation != null ||
          (peer.cachedLatitude != null && peer.cachedLongitude != null)) {
        setState(() {
          _usingCachedPeerLocation = true;
          _networkBanner = e.offline
              ? 'No signal — last known position ${_formatClock(_peerLocationFetchedAt ?? peer.cachedAt)}'
              : e.message;
          if (_livePeerLocation == null &&
              peer.cachedLatitude != null &&
              peer.cachedLongitude != null) {
            _livePeerLocation = PeerLocation(
              userId: peer.userId,
              latitude: peer.cachedLatitude!,
              longitude: peer.cachedLongitude!,
              timestamp: peer.cachedAt,
              fetchedAt: peer.cachedAt,
            );
            _peerLocationFetchedAt = peer.cachedAt;
          }
        });
      } else {
        setState(() => _networkBanner = e.message);
      }
    }
  }

  /// Peer lat/lng with short dead-reckoning coast between network polls.
  ({double lat, double lng})? _effectivePeerPoint() {
    final target = _livePeerLocation;
    if (target == null) return null;
    final coast = extrapolatePeerPosition(
      lat: target.latitude,
      lng: target.longitude,
      speedMps: target.speed,
      headingDegrees: target.heading,
      fixTime: target.timestamp,
    );
    if (coast != null) return coast;
    return (lat: target.latitude, lng: target.longitude);
  }

  void _startGpsSearchTimer() {
    _gpsSearchTimer?.cancel();
    _gpsSearchTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted || _currentPosition != null || !_isCompassActive) return;
      setState(() => _gpsSearchTimeout = true);
    });
  }

  void _cancelGpsSearchTimer() {
    _gpsSearchTimer?.cancel();
    _gpsSearchTimer = null;
  }

  double? _distanceToTarget() {
    final me = _currentPosition ?? _lastKnownPosition;
    final target = _effectivePeerPoint();
    if (me == null || target == null) return null;
    return haversineMeters(
      me.latitude,
      me.longitude,
      target.lat,
      target.lng,
    );
  }

  double? _arrowRotationDegrees() {
    final me = _currentPosition ?? _lastKnownPosition;
    final target = _effectivePeerPoint();
    if (me == null || target == null || _deviceHeading == null) return null;
    final bearing = Geolocator.bearingBetween(
      me.latitude,
      me.longitude,
      target.lat,
      target.lng,
    );
    return (bearing - _deviceHeading! + 360) % 360;
  }

  // --- Menu ---

  void _toggleMenu(_MenuButton button) {
    if (_activeMenuButton == button) {
      _goToDefault();
      return;
    }
    _stopCompassTracking();
    setState(() {
      _editingPeer = null;
      _compassPeer = null;
      switch (button) {
        case _MenuButton.list:
          _mode = _ScreenMode.people;
        case _MenuButton.add:
          _mode = _ScreenMode.add;
        case _MenuButton.edit:
          _mode = _ScreenMode.editList;
        case _MenuButton.info:
          _mode = _ScreenMode.info;
      }
    });
    unawaited(_ensureLocationSharing());
    _startPendingWatcher();
    if (button == _MenuButton.list || button == _MenuButton.edit) {
      unawaited(_refreshPeers());
    }
  }

  Future<void> _scanAndPair() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => QrScanScreen(palette: _palette)),
    );
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      await _network.requestPairFromQr(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pairing request sent. Waiting for acceptance.'),
        ),
      );
      await _refreshPeers();
    } on NetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _renameProfile(String name) async {
    if (_profile == null || name.trim().isEmpty) return;
    final clean = name.trim();
    try {
      final updated = await _network.updateProfileName(clean);
      await _store.saveProfile(updated);
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile name saved')),
      );
    } on NetworkException catch (e) {
      final local = _profile!.copyWith(name: clean);
      await _store.saveProfile(local);
      _network.setProfile(local);
      if (!mounted) return;
      setState(() => _profile = local);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved locally (${e.message})')),
      );
    }
  }

  Future<void> _saveEditedPeer(Peer peer, String displayName) async {
    try {
      await _network.renamePeer(peer.userId, displayName);
      await _refreshPeers();
      if (!mounted) return;
      setState(() {
        _mode = _ScreenMode.editList;
        _editingPeer = null;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deletePeer(Peer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _palette.containerBackground,
        title: Text('Unpair?', style: TextStyle(color: _palette.textPrimary)),
        content: Text(
          'Remove the connection with "${peer.displayName}"? '
          'You will disappear from each other\'s lists.',
          style: TextStyle(color: _palette.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Unpair', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _network.unpair(peer.userId);
      await _refreshPeers();
      if (_editingPeer?.userId == peer.userId && mounted) {
        setState(() {
          _mode = _ScreenMode.editList;
          _editingPeer = null;
        });
      }
    } on NetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        if (_bootstrapping) {
          return Scaffold(
            backgroundColor: _palette.background,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: _palette.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildLogoHeader(),
                if (_networkBanner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      _networkBanner!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                    ),
                  ),
                Expanded(child: _buildCenterContainer()),
                _buildBottomArea(),
                _GpsBar(
                  palette: _palette,
                  position: _currentPosition ?? _lastKnownPosition,
                  statusMessage: _gpsStatusMessage,
                  sharingActive: _locationShare.isRunning,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 22.8),
      child: SizedBox(
        height: _kHeaderTitleHeight,
        child: Center(
          child: Text(
            'Medicine Compass',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: _palette.textPrimary,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterContainer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _palette.containerBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _palette.surfaceBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildCenterContent(),
        ),
      ),
    );
  }

  Widget _buildCenterContent() {
    switch (_mode) {
      case _ScreenMode.people:
        return _PeopleListView(
          palette: _palette,
          peers: _peers,
          showEditControls: false,
          onTap: _openCompass,
          onRefresh: _refreshPeers,
        );
      case _ScreenMode.add:
        return _PairingTab(
          palette: _palette,
          profile: _profile,
          onScan: _scanAndPair,
          onRenameProfile: _renameProfile,
        );
      case _ScreenMode.editList:
        return _PeopleListView(
          palette: _palette,
          peers: _peers,
          showEditControls: true,
          onTap: (_) {},
          onEdit: (p) => setState(() {
            _mode = _ScreenMode.editItem;
            _editingPeer = p;
          }),
          onDelete: _deletePeer,
          onRefresh: _refreshPeers,
        );
      case _ScreenMode.editItem:
        if (_editingPeer == null) return const SizedBox.shrink();
        return _EditPeerForm(
          palette: _palette,
          peer: _editingPeer!,
          onSave: (name) => _saveEditedPeer(_editingPeer!, name),
          onDelete: () => _deletePeer(_editingPeer!),
          onBack: () => setState(() {
            _mode = _ScreenMode.editList;
            _editingPeer = null;
          }),
        );
      case _ScreenMode.info:
        return _InfoContent(settings: widget.settings);
      case _ScreenMode.compass:
        return _CompassView(
          palette: _palette,
          peer: _compassPeer!,
          errorMessage: _compassError,
          permissionGranted: _compassPermissionGranted,
          currentPosition: _currentPosition ?? _lastKnownPosition,
          deviceHeading: _deviceHeading,
          gpsSearchTimeout: _gpsSearchTimeout,
          distance: _distanceToTarget(),
          rotation: _arrowRotationDegrees(),
          usingCachedLocation: _usingCachedPeerLocation,
          locationFetchedAt: _peerLocationFetchedAt,
        );
    }
  }

  Widget _buildBottomArea() {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardBottom > 0) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, keyboardBottom + 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: _KeyboardDismissButton(palette: _palette),
        ),
      );
    }

    if (_mode == _ScreenMode.compass) {
      return _buildCompassFooter();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _buildMenuButton(_MenuButton.list, 'List', Icons.list),
          const SizedBox(width: 8),
          _buildMenuButton(_MenuButton.add, 'Add', Icons.qr_code_2),
          const SizedBox(width: 8),
          _buildMenuButton(_MenuButton.edit, 'Edit', Icons.edit),
          const SizedBox(width: 8),
          _buildMenuButton(_MenuButton.info, 'Info', Icons.info_outline),
        ],
      ),
    );
  }

  Widget _buildMenuButton(_MenuButton button, String label, IconData icon) {
    final isActive = _activeMenuButton == button;
    return Expanded(
      child: SizedBox(
        height: _kSquareButtonSize,
        child: _SquareMenuButton(
          palette: _palette,
          label: label,
          icon: icon,
          isActive: isActive,
          onPressed: () => _toggleMenu(button),
        ),
      ),
    );
  }

  Widget _buildCompassFooter() {
    final distance = _distanceToTarget();
    final isReady = _compassPermissionGranted &&
        (_currentPosition != null || _lastKnownPosition != null) &&
        _livePeerLocation != null &&
        _deviceHeading != null &&
        _compassError == null;

    final bool arrived = isReady && distance != null && distance <= arrivalRadiusMeters;
    final bool showDistance = isReady && !arrived;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: arrived
                ? Text(
                    'Destination reached — look around.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _palette.textPrimary,
                    ),
                  )
                : showDistance
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Distance',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _palette.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDistanceValue(distance),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _palette.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDistanceUnit(distance),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _palette.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _gpsSearchTimeout
                            ? 'Start walking to help establish a GPS connection'
                            : 'Calculating satellite signals',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _palette.textPrimary,
                        ),
                      ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: SizedBox(
                width: _kSquareButtonSize,
                height: _kSquareButtonSize,
                child: _SquareMenuButton(
                  palette: _palette,
                  label: 'Back',
                  icon: Icons.keyboard_arrow_down,
                  labelAboveIcon: true,
                  onPressed: _goToDefault,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _KeyboardDismissButton extends StatelessWidget {
  const _KeyboardDismissButton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final fg = palette.buttonForeground;
    return Material(
      color: palette.buttonBackground,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('hide', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.1, color: fg)),
                  Text('keyboard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.1, color: fg)),
                ],
              ),
              const SizedBox(width: 10),
              Icon(Icons.keyboard_arrow_down, size: 22, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareMenuButton extends StatelessWidget {
  const _SquareMenuButton({
    required this.palette,
    required this.icon,
    required this.onPressed,
    this.label,
    this.labelAboveIcon = false,
    this.isActive = false,
  });

  final AppPalette palette;
  final IconData icon;
  final VoidCallback onPressed;
  final String? label;
  final bool labelAboveIcon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final foreground = isActive
        ? (palette.isDark ? Colors.black : Colors.white)
        : palette.buttonForeground;
    final background = isActive ? palette.accent : palette.buttonBackground;

    final content = label == null
        ? Center(child: Icon(icon, size: 32, color: foreground))
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (labelAboveIcon) ...[
                Text(label!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: foreground)),
                const SizedBox(height: 4),
                Icon(icon, size: 28, color: foreground),
              ] else ...[
                Icon(icon, size: 28, color: foreground),
                const SizedBox(height: 4),
                Text(label!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: foreground)),
              ],
            ],
          );

    return AnimatedContainer(
      duration: _kMenuAnimDuration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      ),
    );
  }
}

class _GpsBar extends StatelessWidget {
  const _GpsBar({
    required this.palette,
    required this.position,
    required this.statusMessage,
    this.sharingActive = false,
  });

  final AppPalette palette;
  final Position? position;
  final String? statusMessage;
  final bool sharingActive;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (statusMessage != null) {
      text = statusMessage!;
    } else if (position != null) {
      final share = sharingActive ? ' · sharing' : '';
      text =
          'Your position: ${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}$share';
    } else if (sharingActive) {
      text = 'Sharing location in background…';
    } else {
      text = 'Searching for your GPS position...';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: palette.gpsBar,
      child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

// ---------------------------------------------------------------------------
// People list
// ---------------------------------------------------------------------------

class _PeopleListView extends StatelessWidget {
  const _PeopleListView({
    required this.palette,
    required this.peers,
    required this.showEditControls,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onRefresh,
  });

  final AppPalette palette;
  final List<Peer> peers;
  final bool showEditControls;
  final ValueChanged<Peer> onTap;
  final ValueChanged<Peer>? onEdit;
  final ValueChanged<Peer>? onDelete;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  showEditControls ? 'Edit people' : 'People',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  onPressed: () => onRefresh?.call(),
                  icon: Icon(Icons.refresh, color: palette.accent),
                ),
            ],
          ),
        ),
        Expanded(
          child: peers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No paired people yet.\nGo to Add and scan a QR code.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => onRefresh?.call() ?? Future.value(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: peers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final peer = peers[index];
                      return Material(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: showEditControls ? null : () => onTap(peer),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.person_pin_circle, size: 28, color: palette.accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        peer.displayName,
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        peer.lastActivityLabel,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (showEditControls) ...[
                                  IconButton(
                                    onPressed: () => onEdit?.call(peer),
                                    icon: Icon(Icons.edit_outlined, color: palette.accent, size: 28),
                                  ),
                                  IconButton(
                                    onPressed: () => onDelete?.call(peer),
                                    icon: Icon(Icons.link_off, color: Colors.red.shade400, size: 28),
                                  ),
                                ] else
                                  Icon(Icons.chevron_right, color: palette.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// QR pairing tab
// ---------------------------------------------------------------------------

class _PairingTab extends StatefulWidget {
  const _PairingTab({
    required this.palette,
    required this.profile,
    required this.onScan,
    required this.onRenameProfile,
  });

  final AppPalette palette;
  final UserProfile? profile;
  final Future<void> Function() onScan;
  final ValueChanged<String> onRenameProfile;

  @override
  State<_PairingTab> createState() => _PairingTabState();
}

class _PairingTabState extends State<_PairingTab> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
  }

  @override
  void didUpdateWidget(covariant _PairingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile?.name != oldWidget.profile?.name &&
        widget.profile?.name != _nameController.text) {
      _nameController.text = widget.profile?.name ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your QR code', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Show this code to another person to pair with them.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: TextStyle(color: widget.palette.textPrimary, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Profile name',
              labelStyle: TextStyle(color: widget.palette.textSecondary),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(Icons.save_outlined, color: widget.palette.accent),
                onPressed: () => widget.onRenameProfile(_nameController.text),
              ),
            ),
            onSubmitted: widget.onRenameProfile,
          ),
          const SizedBox(height: 16),
          if (profile != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: profile.toQrPayload(),
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (profile != null) ...[
            const SizedBox(height: 10),
            Text(
              profile.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.palette.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Scan QR code', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Scan a friend\'s code — we will send a two-way pairing request.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.palette.accent,
              foregroundColor: widget.palette.isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CameraPermissionState { checking, denied, permanentlyDenied, granted, error }

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.palette});

  final AppPalette palette;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<Object?>? _barcodeSub;
  bool _handled = false;
  bool _starting = false;
  _CameraPermissionState _permissionState = _CameraPermissionState.checking;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.qrCode],
    );
    unawaited(_prepareCamera());
  }

  Future<void> _prepareCamera() async {
    setState(() {
      _permissionState = _CameraPermissionState.checking;
      _permissionError = null;
    });

    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (!mounted) return;

      if (status.isPermanentlyDenied) {
        setState(() => _permissionState = _CameraPermissionState.permanentlyDenied);
        return;
      }
      if (!status.isGranted) {
        setState(() => _permissionState = _CameraPermissionState.denied);
        return;
      }

      setState(() => _permissionState = _CameraPermissionState.granted);
      await _startScanner();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionState = _CameraPermissionState.error;
        _permissionError = e.toString();
      });
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _starting || _handled) return;
    _starting = true;
    try {
      await _barcodeSub?.cancel();
      _barcodeSub = _controller.barcodes.listen(_onDetect);
      // Wait one frame so the MobileScanner widget is attached.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || _handled) return;
      await _controller.start();
      if (mounted) {
        setState(() {
          _permissionState = _CameraPermissionState.granted;
          _permissionError = null;
        });
      }
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionState = _CameraPermissionState.error;
        _permissionError = e.errorDetails?.message ?? e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionState = _CameraPermissionState.error;
        _permissionError = e.toString();
      });
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopScanner() async {
    await _barcodeSub?.cancel();
    _barcodeSub = null;
    try {
      await _controller.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_permissionState != _CameraPermissionState.granted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_stopScanner());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_barcodeSub?.cancel());
    _barcodeSub = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    unawaited(_stopScanner());
    if (mounted) Navigator.of(context).pop(raw);
  }

  Widget _buildMessageBody({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final palette = widget.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: palette.accent),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: palette.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_permissionState) {
      case _CameraPermissionState.checking:
        return _buildMessageBody(
          icon: Icons.hourglass_top,
          title: 'Starting camera…',
          message: 'Checking camera permission.',
        );
      case _CameraPermissionState.denied:
        return _buildMessageBody(
          icon: Icons.camera_alt_outlined,
          title: 'Camera access needed',
          message: 'Medicine Compass needs camera access to scan QR codes for pairing.',
          actionLabel: 'Grant permission',
          onAction: () => unawaited(_prepareCamera()),
        );
      case _CameraPermissionState.permanentlyDenied:
        return _buildMessageBody(
          icon: Icons.no_photography_outlined,
          title: 'Camera access denied',
          message: 'Enable camera permission in your device settings to scan QR codes.',
          actionLabel: 'Open settings',
          onAction: () => unawaited(openAppSettings()),
        );
      case _CameraPermissionState.error:
        return _buildMessageBody(
          icon: Icons.videocam_off,
          title: 'Camera unavailable',
          message: _permissionError ??
              'Could not start the camera. Close other camera apps and try again.',
          actionLabel: 'Try again',
          onAction: () => unawaited(_prepareCamera()),
        );
      case _CameraPermissionState.granted:
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              errorBuilder: (context, error) {
                return _buildMessageBody(
                  icon: Icons.videocam_off,
                  title: 'Camera unavailable',
                  message: error.errorDetails?.message ??
                      'Could not start the camera. Please try again.',
                  actionLabel: 'Try again',
                  onAction: () => unawaited(_prepareCamera()),
                );
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'Point the camera at your friend\'s QR code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: const Text('Scan QR code'),
      ),
      body: _buildBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit person
// ---------------------------------------------------------------------------

class _EditPeerForm extends StatefulWidget {
  const _EditPeerForm({
    required this.palette,
    required this.peer,
    required this.onSave,
    required this.onDelete,
    required this.onBack,
  });

  final AppPalette palette;
  final Peer peer;
  final ValueChanged<String> onSave;
  final VoidCallback onDelete;
  final VoidCallback onBack;

  @override
  State<_EditPeerForm> createState() => _EditPeerFormState();
}

class _EditPeerFormState extends State<_EditPeerForm> {
  late final TextEditingController _nameController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.peer.displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a display name.');
      return;
    }
    widget.onSave(name);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back, color: widget.palette.accent),
              ),
              Text('Edit person', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Profile: ${widget.peer.name}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: TextStyle(fontSize: 18, color: widget.palette.textPrimary),
            decoration: InputDecoration(
              labelText: 'Display name',
              labelStyle: TextStyle(color: widget.palette.textSecondary),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade400)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.palette.accent,
              foregroundColor: widget.palette.isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Save changes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: Icon(Icons.link_off, color: Colors.red.shade400),
            label: Text('Unpair', style: TextStyle(color: Colors.red.shade400)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info
// ---------------------------------------------------------------------------

class _InfoContent extends StatelessWidget {
  const _InfoContent({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final palette = settings.palette;
        final body = Theme.of(context).textTheme.bodyLarge;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('How navigation works', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'While Medicine Compass is running — even in the background — '
                      'your phone uploads your GPS so paired friends can find you. '
                      'Open someone from the list to see a live arrow and distance to them.',
                      style: body,
                    ),
                    const SizedBox(height: 20),
                    Text('QR code pairing', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'In the Add tab, show your QR code or scan a friend\'s code. '
                      'After scanning, the other person must accept the connection. '
                      'Only then does the relationship work both ways — you appear on each other\'s lists.',
                      style: body,
                    ),
                    const SizedBox(height: 20),
                    Text('Background sharing', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Your location is shared while the app process is alive (including when you switch apps). '
                      'Uploads adapt to movement: sparse when you stand still, denser when you walk or open the compass. '
                      'Android shows a persistent notification so GPS can keep running. '
                      'The compass view polls a friend only as often as distance and speed require, '
                      'and skips downloading when their position has not changed. '
                      'Force-closing the app stops sharing.',
                      style: body,
                    ),
                    const SizedBox(height: 32),
                    Text('Theme', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _ThemeOption(
                      palette: palette,
                      label: 'Dark',
                      selected: palette.isDark,
                      onTap: () => settings.setTheme(AppThemeMode.dark),
                    ),
                    const SizedBox(height: 8),
                    _ThemeOption(
                      palette: palette,
                      label: 'Light',
                      selected: !palette.isDark,
                      onTap: () => settings.setTheme(AppThemeMode.light),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text(
                'author: kamilszadejko@gmail.com',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.surfaceBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: palette.accent,
              ),
              const SizedBox(width: 12),
              Text(label, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compass view
// ---------------------------------------------------------------------------

class _CompassView extends StatelessWidget {
  const _CompassView({
    required this.palette,
    required this.peer,
    required this.errorMessage,
    required this.permissionGranted,
    required this.currentPosition,
    required this.deviceHeading,
    required this.gpsSearchTimeout,
    required this.distance,
    required this.rotation,
    required this.usingCachedLocation,
    required this.locationFetchedAt,
  });

  final AppPalette palette;
  final Peer peer;
  final String? errorMessage;
  final bool permissionGranted;
  final Position? currentPosition;
  final double? deviceHeading;
  final bool gpsSearchTimeout;
  final double? distance;
  final double? rotation;
  final bool usingCachedLocation;
  final DateTime? locationFetchedAt;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return _msg(Icons.location_off, Colors.red.shade400, errorMessage!);
    }

    if (!permissionGranted || currentPosition == null) {
      final text = gpsSearchTimeout
          ? 'Start walking to help establish a GPS connection'
          : 'Calculating satellite signals';
      return _msg(Icons.gps_fixed, palette.accent, text);
    }

    if (deviceHeading == null) {
      return _msg(Icons.explore, palette.accent, 'Calibrating compass...\nMove your phone in a figure-eight.');
    }

    if (distance == null) {
      return _msg(
        Icons.cloud_off,
        palette.accent,
        usingCachedLocation
            ? 'No current location for this person.\nLast known: ${_formatClock(locationFetchedAt)}'
            : 'Fetching person\'s location...',
      );
    }

    if (distance! <= arrivalRadiusMeters) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 160, color: palette.success),
            const SizedBox(height: 24),
            Text(
              'Destination reached — look around.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            peer.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (usingCachedLocation && locationFetchedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last known position: ${_formatClock(locationFetchedAt)}',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          Transform.rotate(
            angle: (rotation ?? 0) * math.pi / 180,
            child: Icon(Icons.arrow_upward_rounded, size: 200, color: palette.arrow),
          ),
        ],
      ),
    );
  }

  Widget _msg(IconData icon, Color color, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: color),
            const SizedBox(height: 24),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, color: palette.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
