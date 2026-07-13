import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Stałe
// ---------------------------------------------------------------------------

const double arrivalRadiusMeters = 5.0;
const String _destinationsKey = 'custom_destinations';
const String _themeKey = 'app_theme';
const String _logoAsset = 'ikona-szadejkompas2.1.png';
const Duration _kMenuAnimDuration = Duration(milliseconds: 400);
const double _kMenuButtonFullHeight = 60;
const double _kMenuIconArea = 26;

const Destination initialDefaultDestination = Destination(
  id: 'default_hasior_birds',
  name: 'Park Kasprowicza — Ogniste Ptaki Hasiora',
  latitude: 53.444760,
  longitude: 14.532817,
);

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
  Color get cofBackground => const Color(0xFFFFE8E8);
  Color get cofForeground => const Color(0xFFB71C1C);
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

  AppThemeMode get theme => _theme;
  AppPalette get palette => AppPalette(_theme);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _theme = prefs.getString(_themeKey) == 'light' ? AppThemeMode.light : AppThemeMode.dark;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode mode) async {
    _theme = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode == AppThemeMode.light ? 'light' : 'dark');
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
          home: MainScreen(settings: settings),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Model i storage
// ---------------------------------------------------------------------------

class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;

  Destination copyWith({String? name, double? latitude, double? longitude}) {
    return Destination(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class DestinationStorage {
  Future<List<Destination>> loadDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_destinationsKey);
    if (raw == null || raw.isEmpty) {
      final defaults = [initialDefaultDestination];
      await saveDestinations(defaults);
      return defaults;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Destination.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveDestinations(List<Destination> destinations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _destinationsKey,
      jsonEncode(destinations.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> addDestination(Destination destination) async {
    final current = await loadDestinations();
    current.add(destination);
    await saveDestinations(current);
  }

  Future<void> updateDestination(Destination destination) async {
    final current = await loadDestinations();
    final index = current.indexWhere((d) => d.id == destination.id);
    if (index == -1) return;
    current[index] = destination;
    await saveDestinations(current);
  }

  Future<void> removeDestination(String id) async {
    final current = await loadDestinations();
    current.removeWhere((d) => d.id == id);
    await saveDestinations(current);
  }

  Future<void> moveDestination(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex) return;
    final current = await loadDestinations();
    if (fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= current.length ||
        toIndex >= current.length) {
      return;
    }
    final item = current.removeAt(fromIndex);
    current.insert(toIndex, item);
    await saveDestinations(current);
  }
}

// ---------------------------------------------------------------------------
// Tryby ekranu
// ---------------------------------------------------------------------------

enum _ScreenMode { destinations, add, editList, editItem, info, compass }

enum _MenuButton { add, edit, info }

// ---------------------------------------------------------------------------
// Główny ekran
// ---------------------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final DestinationStorage _storage = DestinationStorage();

  _ScreenMode _mode = _ScreenMode.destinations;
  List<Destination> _destinations = [];
  Destination? _compassDestination;
  Destination? _editingDestination;

  Position? _currentPosition;
  String? _gpsStatusMessage;
  double? _deviceHeading;
  String? _compassError;
  bool _compassPermissionGranted = false;
  bool _gpsSearchTimeout = false;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _gpsSearchTimer;

  AppPalette get _palette => widget.settings.palette;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _initializeGps();
  }

  @override
  void dispose() {
    _cancelGpsSearchTimer();
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    final saved = await _storage.loadDestinations();
    if (!mounted) return;
    setState(() => _destinations = saved);
  }

  void _goToDefault() {
    setState(() {
      _mode = _ScreenMode.destinations;
      _compassDestination = null;
      _editingDestination = null;
      _compassError = null;
      _gpsSearchTimeout = false;
    });
    _stopCompassSensors();
  }

  _MenuButton? get _activeMenuButton {
    switch (_mode) {
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

  // --- GPS ---

  Future<void> _initializeGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsStatusMessage = 'GPS wyłączony — włącz lokalizację w ustawieniach.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _gpsStatusMessage = 'Brak dostępu do lokalizacji.');
      return;
    }

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() {
          _currentPosition = position;
          _gpsStatusMessage = null;
          if (_mode == _ScreenMode.compass) {
            _gpsSearchTimeout = false;
          }
        });
        if (_mode == _ScreenMode.compass) _cancelGpsSearchTimer();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _gpsStatusMessage = 'Nie udało się odczytać pozycji GPS.');
      },
    );
  }

  void _startGpsSearchTimer() {
    _gpsSearchTimer?.cancel();
    _gpsSearchTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted || _currentPosition != null) return;
      setState(() => _gpsSearchTimeout = true);
    });
  }

  void _cancelGpsSearchTimer() {
    _gpsSearchTimer?.cancel();
    _gpsSearchTimer = null;
  }

  // --- Kompas ---

  void _openCompass(Destination destination) {
    setState(() {
      _mode = _ScreenMode.compass;
      _compassDestination = destination;
      _compassError = null;
      _gpsSearchTimeout = false;
      _deviceHeading = null;
    });
    _startCompassSensors();
  }

  Future<void> _startCompassSensors() async {
    _startGpsSearchTimer();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _compassError = 'Włącz lokalizację GPS w ustawieniach telefonu.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _compassError = 'Brak dostępu do lokalizacji.');
      return;
    }

    setState(() {
      _compassPermissionGranted = true;
      _compassError = null;
    });

    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (!mounted) return;
        final heading = event.heading;
        if (heading != null) setState(() => _deviceHeading = heading);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _compassError = 'Nie udało się odczytać kompasu.');
      },
    );
  }

  void _stopCompassSensors() {
    _cancelGpsSearchTimer();
    _compassSubscription?.cancel();
    _compassSubscription = null;
  }

  double? _distanceToTarget() {
    if (_currentPosition == null || _compassDestination == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _compassDestination!.latitude,
      _compassDestination!.longitude,
    );
  }

  double? _arrowRotationDegrees() {
    if (_currentPosition == null ||
        _compassDestination == null ||
        _deviceHeading == null) {
      return null;
    }
    final bearing = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _compassDestination!.latitude,
      _compassDestination!.longitude,
    );
    double rotation = bearing - _deviceHeading!;
    return (rotation + 360) % 360;
  }

  // --- Akcje menu ---

  void _toggleMenu(_MenuButton button) {
    if (_activeMenuButton == button) {
      _goToDefault();
      return;
    }
    setState(() {
      _editingDestination = null;
      switch (button) {
        case _MenuButton.add:
          _mode = _ScreenMode.add;
        case _MenuButton.edit:
          _mode = _ScreenMode.editList;
        case _MenuButton.info:
          _mode = _ScreenMode.info;
      }
    });
  }

  Future<void> _addDestination(Destination destination) async {
    await _storage.addDestination(destination);
    await _loadDestinations();
    _goToDefault();
  }

  Future<void> _saveEditedDestination(Destination destination) async {
    await _storage.updateDestination(destination);
    await _loadDestinations();
    setState(() {
      _mode = _ScreenMode.editList;
      _editingDestination = null;
    });
  }

  Future<void> _deleteDestination(Destination destination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _palette.containerBackground,
        title: Text('Usunąć miejsce?', style: TextStyle(color: _palette.textPrimary)),
        content: Text(
          'Czy na pewno usunąć „${destination.name}"?',
          style: TextStyle(color: _palette.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Usuń', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.removeDestination(destination.id);
    await _loadDestinations();
    if (_editingDestination?.id == destination.id) {
      setState(() {
        _mode = _ScreenMode.editList;
        _editingDestination = null;
      });
    }
  }

  Future<void> _moveDestination(int index, int direction) async {
    final target = index + direction;
    if (target < 0 || target >= _destinations.length) return;
    await _storage.moveDestination(index, target);
    await _loadDestinations();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: _palette.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildLogoHeader(),
                Expanded(child: _buildCenterContainer()),
                _buildBottomArea(),
                _GpsBar(
                  palette: _palette,
                  position: _currentPosition,
                  statusMessage: _gpsStatusMessage,
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Image.asset(_logoAsset, height: 72, fit: BoxFit.contain),
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
      case _ScreenMode.destinations:
        return _DestinationsListView(
          palette: _palette,
          destinations: _destinations,
          showEditControls: false,
          onTap: _openCompass,
        );
      case _ScreenMode.add:
        return _AddForm(
          palette: _palette,
          currentPosition: _currentPosition,
          onSave: _addDestination,
        );
      case _ScreenMode.editList:
        return _DestinationsListView(
          palette: _palette,
          destinations: _destinations,
          showEditControls: true,
          onTap: (_) {},
          onEdit: (d) => setState(() {
            _mode = _ScreenMode.editItem;
            _editingDestination = d;
          }),
          onDelete: _deleteDestination,
          onMoveUp: (i) => _moveDestination(i, -1),
          onMoveDown: (i) => _moveDestination(i, 1),
        );
      case _ScreenMode.editItem:
        if (_editingDestination == null) return const SizedBox.shrink();
        return _EditForm(
          palette: _palette,
          destination: _editingDestination!,
          onSave: _saveEditedDestination,
          onDelete: () => _deleteDestination(_editingDestination!),
          onBack: () => setState(() {
            _mode = _ScreenMode.editList;
            _editingDestination = null;
          }),
        );
      case _ScreenMode.info:
        return _InfoContent(settings: widget.settings);
      case _ScreenMode.compass:
        return _CompassView(
          palette: _palette,
          destination: _compassDestination!,
          errorMessage: _compassError,
          permissionGranted: _compassPermissionGranted,
          currentPosition: _currentPosition,
          deviceHeading: _deviceHeading,
          gpsSearchTimeout: _gpsSearchTimeout,
          distance: _distanceToTarget(),
          rotation: _arrowRotationDegrees(),
        );
    }
  }

  Widget _buildBottomArea() {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardBottom > 0) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, keyboardBottom + 4),
        child: _KeyboardDismissButton(palette: _palette),
      );
    }

    if (_mode == _ScreenMode.compass) {
      return _buildCompassFooter();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildMenuColumn(_MenuButton.add, 'Dodaj', Icons.add),
          const SizedBox(width: 8),
          _buildMenuColumn(_MenuButton.edit, 'Edytuj', Icons.edit),
          const SizedBox(width: 8),
          _buildMenuColumn(_MenuButton.info, 'Info', Icons.info_outline),
        ],
      ),
    );
  }

  Widget _buildMenuColumn(_MenuButton button, String label, IconData icon) {
    final isActive = _activeMenuButton == button;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuButtonWidget(
            palette: _palette,
            label: label,
            icon: icon,
            isActive: isActive,
            onPressed: () => _toggleMenu(button),
          ),
          if (isActive) ...[
            const SizedBox(height: 6),
            _CofButton(palette: _palette, onPressed: _goToDefault, compact: true),
          ],
        ],
      ),
    );
  }

  Widget _buildCompassFooter() {
    final distance = _distanceToTarget();
    final isReady = _compassPermissionGranted &&
        _currentPosition != null &&
        _deviceHeading != null &&
        _compassError == null;

    String distanceText;
    if (!isReady) {
      distanceText = _gpsSearchTimeout
          ? 'zacznij iść, aby pomóc w nawiązaniu połączenia GPS'
          : 'kalkulowanie sygnałów z satelitów';
    } else if (distance != null && distance <= arrivalRadiusMeters) {
      distanceText = 'Osiągnięto destynację. Rozejrzyj się.';
    } else {
      distanceText = 'Dystans do destynacji: ${distance?.round() ?? '...'} metrów';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Text(
            distanceText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CofButton(
                  palette: _palette,
                  icon: Icons.arrow_back,
                  onPressed: _goToDefault,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgety wspólne
// ---------------------------------------------------------------------------

class _MenuButtonWidget extends StatelessWidget {
  const _MenuButtonWidget({
    required this.palette,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  final AppPalette palette;
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final activeHeight = _kMenuButtonFullHeight - _kMenuIconArea;

    return AnimatedContainer(
      duration: _kMenuAnimDuration,
      curve: Curves.easeInOut,
      height: isActive ? activeHeight : _kMenuButtonFullHeight,
      transform: Matrix4.translationValues(0, isActive ? -4 : 0, 0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? palette.accent : palette.buttonBackground,
          foregroundColor: isActive
              ? (palette.isDark ? Colors.black : Colors.white)
              : palette.buttonForeground,
          elevation: isActive ? 3 : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: isActive
            ? Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }
}

class _KeyboardDismissButton extends StatelessWidget {
  const _KeyboardDismissButton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
        icon: Icon(Icons.keyboard_arrow_down, color: palette.textPrimary, size: 28),
        label: Text(
          'Zamknij klawiaturę',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.buttonBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _CofButton extends StatelessWidget {
  const _CofButton({
    required this.palette,
    required this.onPressed,
    this.icon = Icons.arrow_back,
    this.compact = false,
  });

  final AppPalette palette;
  final VoidCallback onPressed;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 36 : 44,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 18 : 22, color: palette.cofForeground),
        label: Text(
          'cof',
          style: TextStyle(
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w600,
            color: palette.cofForeground,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.cofBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  });

  final AppPalette palette;
  final Position? position;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (statusMessage != null) {
      text = statusMessage!;
    } else if (position != null) {
      text =
          'Twoja pozycja: ${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}';
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
// Lista destynacji
// ---------------------------------------------------------------------------

class _DestinationsListView extends StatelessWidget {
  const _DestinationsListView({
    required this.palette,
    required this.destinations,
    required this.showEditControls,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  final AppPalette palette;
  final List<Destination> destinations;
  final bool showEditControls;
  final ValueChanged<Destination> onTap;
  final ValueChanged<Destination>? onEdit;
  final ValueChanged<Destination>? onDelete;
  final ValueChanged<int>? onMoveUp;
  final ValueChanged<int>? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Destynacje',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: destinations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Brak zapisanych miejsc.\nNaciśnij „dodaj destynację".',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: destinations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final d = destinations[index];
                    final showArrows = destinations.length > 1;
                    final canUp = showArrows && index > 0;
                    final canDown = showArrows && index < destinations.length - 1;

                    return Material(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: showEditControls ? null : () => onTap(d),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          child: Row(
                            children: [
                              if (showEditControls && showArrows) ...[
                                SizedBox(
                                  width: 40,
                                  child: Column(
                                    children: [
                                      if (canUp)
                                        IconButton(
                                          onPressed: () => onMoveUp?.call(index),
                                          icon: Icon(Icons.arrow_upward, color: palette.accent),
                                          iconSize: 26,
                                        ),
                                      if (canDown)
                                        IconButton(
                                          onPressed: () => onMoveDown?.call(index),
                                          icon: Icon(Icons.arrow_downward, color: palette.accent),
                                          iconSize: 26,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              Icon(Icons.place, size: 28, color: palette.accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(d.name, style: Theme.of(context).textTheme.titleLarge),
                              ),
                              if (showEditControls) ...[
                                IconButton(
                                  onPressed: () => onEdit?.call(d),
                                  icon: Icon(Icons.edit_outlined, color: palette.accent, size: 28),
                                ),
                                IconButton(
                                  onPressed: () => onDelete?.call(d),
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 28),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Formularz dodawania
// ---------------------------------------------------------------------------

class _AddForm extends StatefulWidget {
  const _AddForm({
    required this.palette,
    required this.currentPosition,
    required this.onSave,
  });

  final AppPalette palette;
  final Position? currentPosition;
  final ValueChanged<Destination> onSave;

  @override
  State<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<_AddForm> {
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _fillFromGps();
  }

  @override
  void didUpdateWidget(_AddForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPosition != null &&
        oldWidget.currentPosition != widget.currentPosition &&
        _latController.text.isEmpty) {
      _fillFromGps();
    }
  }

  void _fillFromGps() {
    final p = widget.currentPosition;
    if (p == null) return;
    _latController.text = p.latitude.toStringAsFixed(6);
    _lngController.text = p.longitude.toStringAsFixed(6);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _copyCoords() {
    final lat = _latController.text.trim();
    final lng = _lngController.text.trim();
    if (lat.isEmpty || lng.isEmpty) return;
    Clipboard.setData(ClipboardData(text: '$lat, $lng'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skopiowano współrzędne'), duration: Duration(seconds: 2)),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Podaj nazwę miejsca.');
      return;
    }
    final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      setState(() => _error = 'Wpisz poprawne współrzędne.');
      return;
    }
    widget.onSave(Destination(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      latitude: lat,
      longitude: lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dodaj miejsce', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          _TextField(controller: _nameController, label: 'Nazwa miejsca', palette: widget.palette),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _fillFromGps,
            icon: Icon(Icons.my_location, color: widget.palette.accent),
            label: Text('Zapisz tutaj, gdzie stoję', style: TextStyle(color: widget.palette.accent)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: widget.palette.accent)),
          ),
          const SizedBox(height: 16),
          _CoordsBox(
            latController: _latController,
            lngController: _lngController,
            onCopy: _copyCoords,
            palette: widget.palette,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade400, fontSize: 16)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.palette.accent,
            foregroundColor: widget.palette.isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Zapisz', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formularz edycji
// ---------------------------------------------------------------------------

class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.palette,
    required this.destination,
    required this.onSave,
    required this.onDelete,
    required this.onBack,
  });

  final AppPalette palette;
  final Destination destination;
  final ValueChanged<Destination> onSave;
  final VoidCallback onDelete;
  final VoidCallback onBack;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.destination.name);
    _latController =
        TextEditingController(text: widget.destination.latitude.toStringAsFixed(6));
    _lngController =
        TextEditingController(text: widget.destination.longitude.toStringAsFixed(6));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _copyCoords() {
    Clipboard.setData(ClipboardData(
      text: '${_latController.text.trim()}, ${_lngController.text.trim()}',
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skopiowano współrzędne'), duration: Duration(seconds: 2)),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Podaj nazwę.');
      return;
    }
    final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      setState(() => _error = 'Wpisz poprawne współrzędne.');
      return;
    }
    widget.onSave(widget.destination.copyWith(name: name, latitude: lat, longitude: lng));
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
              IconButton(onPressed: widget.onBack, icon: Icon(Icons.arrow_back, color: widget.palette.accent)),
              Text('Edytuj miejsce', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: 8),
          _TextField(controller: _nameController, label: 'Nazwa miejsca', palette: widget.palette),
          const SizedBox(height: 16),
          _CoordsBox(
            latController: _latController,
            lngController: _lngController,
            onCopy: _copyCoords,
            palette: widget.palette,
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
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            label: Text('Usuń', style: TextStyle(color: Colors.red.shade400)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}

class _CoordsBox extends StatelessWidget {
  const _CoordsBox({
    required this.latController,
    required this.lngController,
    required this.onCopy,
    this.palette,
    this.darkText = false,
  });

  final TextEditingController latController;
  final TextEditingController lngController;
  final VoidCallback onCopy;
  final AppPalette? palette;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final accent = palette?.accent ?? const Color(0xFF0D47A1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 2),
        color: darkText ? const Color(0xFFF8F9FF) : palette?.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Współrzędne',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 10),
          _TextField(
            controller: latController,
            label: 'Szerokość',
            palette: palette,
            darkText: darkText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
          ),
          const SizedBox(height: 10),
          _TextField(
            controller: lngController,
            label: 'Długość',
            palette: palette,
            darkText: darkText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: Icon(Icons.copy, color: accent),
            label: Text('Kopiuj współrzędne', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: accent)),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.palette,
    this.darkText = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final AppPalette? palette;
  final bool darkText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final textColor = darkText ? Colors.black : (palette?.textPrimary ?? Colors.black);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(fontSize: 18, color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: darkText ? Colors.black54 : palette?.textSecondary),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel informacji
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Szadejkompas działa offline przy użyciu sygnału GPS, '
                'więc jest dokładniejszy gdy się poruszasz.',
                style: Theme.of(context).textTheme.bodyLarge,
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
              const SizedBox(height: 32),
              Text(
                'Author:\nkeiko64x@gmail.com',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
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
// Widok kompasu (w środkowym kontenerze)
// ---------------------------------------------------------------------------

class _CompassView extends StatelessWidget {
  const _CompassView({
    required this.palette,
    required this.destination,
    required this.errorMessage,
    required this.permissionGranted,
    required this.currentPosition,
    required this.deviceHeading,
    required this.gpsSearchTimeout,
    required this.distance,
    required this.rotation,
  });

  final AppPalette palette;
  final Destination destination;
  final String? errorMessage;
  final bool permissionGranted;
  final Position? currentPosition;
  final double? deviceHeading;
  final bool gpsSearchTimeout;
  final double? distance;
  final double? rotation;

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

    if (distance != null && distance! <= arrivalRadiusMeters) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 160, color: palette.success),
            const SizedBox(height: 24),
            Text(
              'Osiągnięto destynację. Rozejrzyj się.',
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
          Text(destination.name,
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
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
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}
