import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'models/peer.dart';
import 'models/user_profile.dart';
import 'services/network_service.dart';
import 'services/profile_store.dart';
import 'utils/polling.dart';

// ---------------------------------------------------------------------------
// Stałe
// ---------------------------------------------------------------------------

const double arrivalRadiusMeters = 5.0;
const String _logoAsset = 'ikony/android/playstore-icon.png';
const Duration _kMenuAnimDuration = Duration(milliseconds: 400);
const double _kWelcomeLogoHeight = 132;
const double _kSquareButtonSize = 72;
const Duration _kPendingPollInterval = Duration(seconds: 20);

String _formatDistanceValue(double? meters) {
  if (meters == null) return '...';
  if (meters <= 1000) return '${meters.round()}';
  return (meters / 1000).toStringAsFixed(2).replaceAll('.', ',');
}

String _formatDistanceUnit(double? meters) {
  if (meters == null) return '';
  return meters <= 1000 ? 'metrów' : 'km';
}

String _formatClock(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

// ---------------------------------------------------------------------------
// Motyw
// ---------------------------------------------------------------------------

enum AppThemeMode { dark, light }

class AppPalette {
  const AppPalette(this.mode);

  final AppThemeMode mode;

  bool get isDark => mode == AppThemeMode.dark;

  Color get background => isDark ? const Color(0xFF12141C) : const Color(0xFFF5F5F5);
  Color get containerBackground => isDark ? const Color(0xFF1E2230) : Colors.white;
  Color get surface => isDark ? const Color(0xFF252A3A) : const Color(0xFFF2F2F2);
  Color get surfaceBorder => isDark ? const Color(0xFF2E3448) : const Color(0xFFD0D0D0);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary => isDark ? const Color(0xFFB8C0D4) : Colors.black87;
  Color get accent => isDark ? const Color(0xFF7EC8FF) : const Color(0xFF0D47A1);
  Color get arrow => isDark ? const Color(0xFF7EC8FF) : const Color(0xFF0D47A1);
  Color get buttonBackground => isDark ? const Color(0xFF2A3145) : const Color(0xFFE8E8E8);
  Color get buttonForeground => isDark ? Colors.white : Colors.black;
  Color get gpsBar => isDark ? const Color(0xFF1A1F2E) : const Color(0xFFE0E0E0);
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
// Aplikacja
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(SzadejkompasApp(settings: settings));
}

class SzadejkompasApp extends StatelessWidget {
  const SzadejkompasApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Szadejkompas',
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
                  Image.asset(_logoAsset, height: _kWelcomeLogoHeight, fit: BoxFit.contain),
                  const SizedBox(height: 32),
                  Text(
                    'Szadejkompas to radar osób w czasie rzeczywistym. '
                    'Sparuj znajomego kodem QR, a po wybraniu go z listy '
                    'nawiguj strzałką do jego aktualnej pozycji GPS.',
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
                            label: 'Rozumiem',
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
                                  'Nie pokazuj ponownie',
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
// Tryby ekranu
// ---------------------------------------------------------------------------

enum _ScreenMode { people, add, editList, editItem, info, compass }

enum _MenuButton { list, add, edit, info }

// ---------------------------------------------------------------------------
// Główny ekran
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

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _gpsSearchTimer;
  Timer? _pollTimer;
  Timer? _pendingTimer;
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
    _enterIdleMode();
    _pendingTimer?.cancel();
    _network.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _enterIdleMode(keepMode: true);
      _pendingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_isCompassActive && _compassPeer != null) {
        _startCompassSession(_compassPeer!);
      } else {
        _startPendingWatcher();
        _refreshPeers();
      }
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
              : 'Nie udało się zarejestrować profilu. Sprawdź sieć.';
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
  }

  Future<String> _defaultDeviceName() async {
    // Prosta, czytelna nazwa profilu — użytkownik może ją zmienić później.
    final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'Telefon $stamp';
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
            ? 'Brak zasięgu — pokazuję ostatnią znaną listę.'
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
            title: Text('Prośba o parowanie', style: TextStyle(color: _palette.textPrimary)),
            content: Text(
              '${request.fromName ?? 'Ktoś'} chce się z Tobą sparować. '
              'Po akceptacji będziecie widoczni u siebie na liście.',
              style: TextStyle(color: _palette.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Odrzuć', style: TextStyle(color: Colors.red.shade400)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Akceptuj', style: TextStyle(color: _palette.accent)),
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
      // ciche — pending nie blokuje UI
    }
  }

  void _goToDefault() {
    _enterIdleMode();
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
    _refreshPeers();
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

  // --- Idle / Compass session ---

  void _enterIdleMode({bool keepMode = false}) {
    _cancelGpsSearchTimer();
    _pollTimer?.cancel();
    _pollTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _compassSubscription?.cancel();
    _compassSubscription = null;
    if (!keepMode) {
      _compassPermissionGranted = false;
      _deviceHeading = null;
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
    _enterIdleMode(keepMode: true);
    _startGpsSearchTimer();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _compassError = 'Włącz lokalizację GPS w ustawieniach telefonu.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _compassError = 'Brak dostępu do lokalizacji.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _compassPermissionGranted = true;
      _compassError = null;
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(
      (position) {
        if (!mounted || !_isCompassActive) return;
        setState(() {
          _currentPosition = position;
          _lastKnownPosition = position;
          _gpsStatusMessage = null;
          _gpsSearchTimeout = false;
        });
        _cancelGpsSearchTimer();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _gpsStatusMessage = 'Nie udało się odczytać pozycji GPS.');
      },
    );

    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (!mounted || !_isCompassActive) return;
        final heading = event.heading;
        if (heading != null) setState(() => _deviceHeading = heading);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _compassError = 'Nie udało się odczytać kompasu.');
      },
    );

    await _pollOnce(peer);
    _scheduleNextPoll(peer);
  }

  void _scheduleNextPoll(Peer peer) {
    _pollTimer?.cancel();
    if (!_isCompassActive) return;
    final distance = _distanceToTarget();
    final wait = pollingIntervalForDistance(distance);
    _pollTimer = Timer(wait, () async {
      if (!_isCompassActive || _compassPeer?.userId != peer.userId) return;
      await _pollOnce(peer);
      _scheduleNextPoll(peer);
    });
  }

  Future<void> _pollOnce(Peer peer) async {
    final me = _currentPosition ?? _lastKnownPosition;
    if (me != null) {
      try {
        await _network.updateLocation(
          lat: me.latitude,
          lng: me.longitude,
          accuracy: me.accuracy,
        );
      } on NetworkException catch (e) {
        if (mounted && e.offline) {
          setState(() => _networkBanner = 'Brak zasięgu — używam ostatniej znanej pozycji.');
        }
      }
    }

    try {
      final loc = await _network.fetchLocation(peer.userId);
      if (!mounted || _compassPeer?.userId != peer.userId) return;
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
              ? 'Brak zasięgu — ostatnia znana pozycja ${_formatClock(_peerLocationFetchedAt ?? peer.cachedAt)}'
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
    final target = _livePeerLocation;
    if (me == null || target == null) return null;
    return haversineMeters(
      me.latitude,
      me.longitude,
      target.latitude,
      target.longitude,
    );
  }

  double? _arrowRotationDegrees() {
    final me = _currentPosition ?? _lastKnownPosition;
    final target = _livePeerLocation;
    if (me == null || target == null || _deviceHeading == null) return null;
    final bearing = Geolocator.bearingBetween(
      me.latitude,
      me.longitude,
      target.latitude,
      target.longitude,
    );
    return (bearing - _deviceHeading! + 360) % 360;
  }

  // --- Menu ---

  void _toggleMenu(_MenuButton button) {
    if (_activeMenuButton == button) {
      _goToDefault();
      return;
    }
    _enterIdleMode();
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
    _startPendingWatcher();
    if (button == _MenuButton.list || button == _MenuButton.edit) {
      _refreshPeers();
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
          content: Text('Wysłano prośbę o parowanie. Poczekaj na akceptację.'),
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
        const SnackBar(content: Text('Zapisano nazwę profilu')),
      );
    } on NetworkException catch (e) {
      final local = _profile!.copyWith(name: clean);
      await _store.saveProfile(local);
      _network.setProfile(local);
      if (!mounted) return;
      setState(() => _profile = local);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zapisano lokalnie (${e.message})')),
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
        title: Text('Odparować?', style: TextStyle(color: _palette.textPrimary)),
        content: Text(
          'Czy na pewno usunąć relację z „${peer.displayName}"? '
          'Znikniecie u siebie z list.',
          style: TextStyle(color: _palette.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Odparuj', style: TextStyle(color: Colors.red.shade400)),
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
                  position: _isCompassActive ? _currentPosition : _lastKnownPosition,
                  statusMessage: _gpsStatusMessage,
                  idleHint: !_isCompassActive,
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
      padding: const EdgeInsets.symmetric(vertical: 11.4, horizontal: 22.8),
      child: Image.asset(_logoAsset, height: 178.6, fit: BoxFit.contain),
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
          _buildMenuButton(_MenuButton.list, 'Lista', Icons.list),
          const SizedBox(width: 8),
          _buildMenuButton(_MenuButton.add, 'Dodaj', Icons.qr_code_2),
          const SizedBox(width: 8),
          _buildMenuButton(_MenuButton.edit, 'Edytuj', Icons.edit),
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
                    'Osiągnięto cel, rozejrzyj się.',
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
                            'Dystans',
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
                            ? 'zacznij iść, aby pomóc w nawiązaniu połączenia GPS'
                            : 'kalkulowanie sygnałów z satelitów',
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
                  label: 'Cofnij',
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
// Widgety wspólne
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
                  Text('schowaj', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.1, color: fg)),
                  Text('klawiaturę', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.1, color: fg)),
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
    this.idleHint = false,
  });

  final AppPalette palette;
  final Position? position;
  final String? statusMessage;
  final bool idleHint;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (statusMessage != null) {
      text = statusMessage!;
    } else if (position != null) {
      text =
          'Twoja pozycja: ${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}';
    } else if (idleHint) {
      text = 'GPS uśpiony — włączy się po wyborze osoby z listy';
    } else {
      text = 'Szukam Twojej pozycji GPS...';
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
// Lista osób
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
                  showEditControls ? 'Edytuj osoby' : 'Osoby',
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
                      'Brak sparowanych osób.\nPrzejdź do „Dodaj” i zeskanuj kod QR.',
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
// Zakładka parowania QR
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
          Text('Twój kod QR', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Pokaż ten kod drugiej osobie, aby Was sparować.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: TextStyle(color: widget.palette.textPrimary, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Nazwa profilu',
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
          Text('Skanuj kod QR', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Zeskanuj kod znajomego — wyślemy prośbę o dwustronne parowanie.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Skanuj kod QR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.palette});

  final AppPalette palette;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
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
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: widget.palette.background,
        title: const Text('Skanuj kod QR'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Skieruj aparat na kod QR znajomego. '
                'Przy pierwszym użyciu zezwól na dostęp do kamery.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edycja osoby
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
      setState(() => _error = 'Podaj nazwę wyświetlaną.');
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
              Text('Edytuj osobę', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Profil: ${widget.peer.name}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: TextStyle(fontSize: 18, color: widget.palette.textPrimary),
            decoration: InputDecoration(
              labelText: 'Nazwa wyświetlana',
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
            child: const Text('Zapisz zmiany', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: Icon(Icons.link_off, color: Colors.red.shade400),
            label: Text('Odparuj', style: TextStyle(color: Colors.red.shade400)),
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
                    Text('Jak działa nawigacja', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Na liście wybierasz sparowaną osobę. Dopiero wtedy Szadejkompas '
                      'włącza GPS i odpytuje serwer domowy o jej ostatnią znaną pozycję. '
                      'Strzałka wskazuje kierunek, a dystans liczony jest na żywo.',
                      style: body,
                    ),
                    const SizedBox(height: 20),
                    Text('Parowanie kodami QR', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'W zakładce „Dodaj” pokaż swój kod QR albo zeskanuj kod znajomego. '
                      'Po skanowaniu druga osoba musi zaakceptować połączenie. '
                      'Dopiero wtedy relacja działa dwustronnie — pojawiacie się u siebie na listach.',
                      style: body,
                    ),
                    const SizedBox(height: 20),
                    Text('Oszczędzanie baterii i danych', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Transmisja pozycji i odpytywanie serwera działają wyłącznie '
                      'przy otwartym widoku kompasu wybranej osoby. W menu Lista / Dodaj / Info '
                      'oraz gdy aplikacja jest w tle GPS przechodzi w uśpienie. '
                      'Częstotliwość odświeżania zależy od dystansu: powyżej 1 km co 60 s, '
                      '100–1000 m co 10 s, poniżej 100 m co 5 s.',
                      style: body,
                    ),
                    const SizedBox(height: 32),
                    Text('Motyw', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _ThemeOption(
                      palette: palette,
                      label: 'Ciemny',
                      selected: palette.isDark,
                      onTap: () => settings.setTheme(AppThemeMode.dark),
                    ),
                    const SizedBox(height: 8),
                    _ThemeOption(
                      palette: palette,
                      label: 'Jasny',
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
                'autor: kamilszadejko@gmail.com',
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
// Widok kompasu
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
          ? 'zacznij iść, aby pomóc w nawiązaniu połączenia GPS'
          : 'kalkulowanie sygnałów z satelitów';
      return _msg(Icons.gps_fixed, palette.accent, text);
    }

    if (deviceHeading == null) {
      return _msg(Icons.explore, palette.accent, 'Kalibruję kompas...\nObróć telefon w kształcie ósemki.');
    }

    if (distance == null) {
      return _msg(
        Icons.cloud_off,
        palette.accent,
        usingCachedLocation
            ? 'Brak aktualnej pozycji osoby.\nOstatnia znana: ${_formatClock(locationFetchedAt)}'
            : 'Pobieram pozycję osoby...',
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
              'Osiągnięto cel, rozejrzyj się.',
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
              'Ostatnia znana pozycja: ${_formatClock(locationFetchedAt)}',
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
