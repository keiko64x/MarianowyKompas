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

const Destination initialDefaultDestination = Destination(
  id: 'default_hasior_birds',
  name: 'Park Kasprowicza — Ogniste Ptaki Hasiora',
  latitude: 53.444760,
  longitude: 14.532817,
);

// ---------------------------------------------------------------------------
// Motyw aplikacji
// ---------------------------------------------------------------------------

enum AppThemeMode { dark, light }

class AppPalette {
  const AppPalette(this.mode);

  final AppThemeMode mode;

  bool get isDark => mode == AppThemeMode.dark;

  Color get background => isDark ? const Color(0xFF12141C) : Colors.white;
  Color get surface => isDark ? const Color(0xFF1E2230) : const Color(0xFFF2F2F2);
  Color get surfaceBorder => isDark ? const Color(0xFF2E3448) : const Color(0xFFD0D0D0);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary => isDark ? const Color(0xFFB8C0D4) : Colors.black87;
  Color get accent => isDark ? const Color(0xFF7EC8FF) : const Color(0xFF0D47A1);
  Color get arrow => isDark ? const Color(0xFF7EC8FF) : const Color(0xFF0D47A1);
  Color get buttonBackground => isDark ? const Color(0xFF2A3145) : const Color(0xFFE8E8E8);
  Color get buttonForeground => isDark ? Colors.white : Colors.black;
  Color get primaryButton => isDark ? const Color(0xFF3D5A80) : const Color(0xFF0D47A1);
  Color get gpsBar => isDark ? const Color(0xFF1A1F2E) : const Color(0xFFE0E0E0);
  Color get dialogBackground => isDark ? const Color(0xFF1E2230) : Colors.white;
  Color get success => Colors.green.shade500;

  ThemeData toThemeData() {
    return ThemeData(
      scaffoldBackgroundColor: background,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          color: textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          color: textSecondary,
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: dialogBackground),
    );
  }
}

class AppSettings extends ChangeNotifier {
  AppThemeMode _theme = AppThemeMode.dark;

  AppThemeMode get theme => _theme;
  AppPalette get palette => AppPalette(_theme);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeKey);
    _theme = saved == 'light' ? AppThemeMode.light : AppThemeMode.dark;
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
        final palette = settings.palette;
        return MaterialApp(
          title: 'Szadejkompas',
          debugShowCheckedModeBanner: false,
          theme: palette.toThemeData(),
          home: PlacesListScreen(settings: settings),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Model miejsca docelowego
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

  Destination copyWith({
    String? name,
    double? latitude,
    double? longitude,
  }) {
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

// ---------------------------------------------------------------------------
// Lokalna baza miejsc
// ---------------------------------------------------------------------------

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
    final encoded = jsonEncode(destinations.map((d) => d.toJson()).toList());
    await prefs.setString(_destinationsKey, encoded);
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
// Ekran listy miejsc
// ---------------------------------------------------------------------------

enum _ActivePanel { none, add, edit, info }

class PlacesListScreen extends StatefulWidget {
  const PlacesListScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<PlacesListScreen> createState() => _PlacesListScreenState();
}

class _PlacesListScreenState extends State<PlacesListScreen> {
  final DestinationStorage _storage = DestinationStorage();
  List<Destination> _destinations = [];
  Position? _currentPosition;
  String? _gpsStatusMessage;
  _ActivePanel _activePanel = _ActivePanel.none;

  StreamSubscription<Position>? _positionSubscription;

  AppPalette get _palette => widget.settings.palette;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _initializeGps();
  }

  Future<void> _loadDestinations() async {
    final saved = await _storage.loadDestinations();
    if (!mounted) return;
    setState(() => _destinations = saved);
  }

  Future<void> _initializeGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _gpsStatusMessage = 'GPS wyłączony — włącz lokalizację w ustawieniach.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _gpsStatusMessage = 'Brak dostępu do lokalizacji.';
      });
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
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _gpsStatusMessage = 'Nie udało się odczytać pozycji GPS.';
        });
      },
    );
  }

  void _togglePanel(_ActivePanel panel) {
    setState(() {
      _activePanel = _activePanel == panel ? _ActivePanel.none : panel;
    });
  }

  Future<void> _addDestination(Destination destination) async {
    await _storage.addDestination(destination);
    await _loadDestinations();
    setState(() => _activePanel = _ActivePanel.none);
  }

  Future<void> _openEditDialog(Destination destination) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => EditDestinationDialog(
        palette: _palette,
        destination: destination,
      ),
    );

    if (result == null) return;
    if (result.deleted) {
      await _storage.removeDestination(destination.id);
    } else if (result.updated != null) {
      await _storage.updateDestination(result.updated!);
    }
    await _loadDestinations();
  }

  Future<void> _moveDestination(int index, int direction) async {
    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= _destinations.length) return;
    await _storage.moveDestination(index, targetIndex);
    await _loadDestinations();
  }

  void _openCompass(Destination destination) {
    if (_activePanel != _ActivePanel.none) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompassScreen(
          settings: widget.settings,
          destination: destination,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  String get _headerTitle {
    switch (_activePanel) {
      case _ActivePanel.add:
        return 'Dodaj miejsce';
      case _ActivePanel.info:
        return 'Informacje';
      case _ActivePanel.edit:
      case _ActivePanel.none:
        return 'Miejsca docelowe';
    }
  }

  Widget _buildCenterContent() {
    switch (_activePanel) {
      case _ActivePanel.add:
        return AddDestinationPanel(
          palette: _palette,
          currentPosition: _currentPosition,
          onSave: _addDestination,
        );
      case _ActivePanel.info:
        return InfoPanel(settings: widget.settings);
      case _ActivePanel.edit:
      case _ActivePanel.none:
        return _buildDestinationsList();
    }
  }

  Widget _buildDestinationsList() {
    if (_destinations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Brak zapisanych miejsc.\nNaciśnij „Dodaj”, aby dodać pierwsze.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      );
    }

    final isEditMode = _activePanel == _ActivePanel.edit;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _destinations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final destination = _destinations[index];
        return _DestinationTile(
          palette: _palette,
          destination: destination,
          isEditMode: isEditMode,
          canMoveUp: index > 0,
          canMoveDown: index < _destinations.length - 1,
          onTap: () => _openCompass(destination),
          onEdit: () => _openEditDialog(destination),
          onMoveUp: () => _moveDestination(index, -1),
          onMoveDown: () => _moveDestination(index, 1),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _palette.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text(
                    _headerTitle,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                Expanded(child: _buildCenterContent()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          palette: _palette,
                          label: 'Dodaj',
                          icon: Icons.add,
                          isActive: _activePanel == _ActivePanel.add,
                          onPressed: () => _togglePanel(_ActivePanel.add),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          palette: _palette,
                          label: 'Edytuj',
                          icon: Icons.edit,
                          isActive: _activePanel == _ActivePanel.edit,
                          onPressed: () => _togglePanel(_ActivePanel.edit),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          palette: _palette,
                          label: 'Informacje',
                          icon: Icons.info_outline,
                          isActive: _activePanel == _ActivePanel.info,
                          onPressed: () => _togglePanel(_ActivePanel.info),
                        ),
                      ),
                    ],
                  ),
                ),
                _CurrentGpsBar(
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
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.palette,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isActive = false,
  });

  final AppPalette palette;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final background = isActive ? palette.accent : palette.buttonBackground;
    final foreground = isActive
        ? (palette.isDark ? Colors.black : Colors.white)
        : palette.buttonForeground;

    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.palette,
    required this.destination,
    required this.isEditMode,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final AppPalette palette;
  final Destination destination;
  final bool isEditMode;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              if (isEditMode) ...[
                Column(
                  children: [
                    IconButton(
                      onPressed: canMoveUp ? onMoveUp : null,
                      icon: Icon(Icons.arrow_upward, color: palette.accent),
                      iconSize: 28,
                      tooltip: 'Przesuń w górę',
                    ),
                    IconButton(
                      onPressed: canMoveDown ? onMoveDown : null,
                      icon: Icon(Icons.arrow_downward, color: palette.accent),
                      iconSize: 28,
                      tooltip: 'Przesuń w dół',
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
              Icon(Icons.place, size: 32, color: palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (isEditMode)
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined, size: 30, color: palette.accent),
                  tooltip: 'Edytuj miejsce',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentGpsBar extends StatelessWidget {
  const _CurrentGpsBar({
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: palette.gpsBar,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel informacji (w środku ekranu)
// ---------------------------------------------------------------------------

class InfoPanel extends StatelessWidget {
  const InfoPanel({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final palette = settings.palette;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Szadejkompas działa offline przy użyciu sygnału GPS, '
                'więc jest dokładniejszy gdy się poruszasz.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'Aplikację stworzył K. Szadejko, dla E. Szadejko, '
                'by mogła odnaleźć M. Szadejko.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 40),
              Text('Motyw', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _ThemeOption(
                palette: palette,
                label: 'Ciemny',
                description: 'Ciemne tło, jasnoniebieska strzałka',
                selected: palette.isDark,
                onTap: () => settings.setTheme(AppThemeMode.dark),
              ),
              const SizedBox(height: 12),
              _ThemeOption(
                palette: palette,
                label: 'Jasny',
                description: 'Białe tło, ciemnoniebieska strzałka',
                selected: !palette.isDark,
                onTap: () => settings.setTheme(AppThemeMode.light),
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
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(description, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel dodawania i dialog edycji miejsca
// ---------------------------------------------------------------------------

enum _AddMode { currentGps, manual }

class _EditResult {
  const _EditResult({this.updated, this.deleted = false});

  final Destination? updated;
  final bool deleted;
}

class AddDestinationPanel extends StatefulWidget {
  const AddDestinationPanel({
    super.key,
    required this.palette,
    required this.currentPosition,
    required this.onSave,
  });

  final AppPalette palette;
  final Position? currentPosition;
  final ValueChanged<Destination> onSave;

  @override
  State<AddDestinationPanel> createState() => _AddDestinationPanelState();
}

class _AddDestinationPanelState extends State<AddDestinationPanel> {
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  _AddMode _mode = _AddMode.currentGps;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _save() {
    final coords = _parseCoordinates();
    if (coords == null) return;

    widget.onSave(
      Destination(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: coords.name,
        latitude: coords.latitude,
        longitude: coords.longitude,
      ),
    );
  }

  ({String name, double latitude, double longitude})? _parseCoordinates() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Podaj nazwę miejsca.');
      return null;
    }

    double latitude;
    double longitude;

    if (_mode == _AddMode.currentGps) {
      final position = widget.currentPosition;
      if (position == null) {
        setState(() => _errorMessage = 'Nie mam jeszcze pozycji GPS. Poczekaj chwilę.');
        return null;
      }
      latitude = position.latitude;
      longitude = position.longitude;
    } else {
      final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
      final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));
      if (lat == null || lng == null) {
        setState(() => _errorMessage = 'Wpisz poprawne współrzędne (np. 53.444760).');
        return null;
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        setState(() => _errorMessage = 'Współrzędne są poza dozwolonym zakresem.');
        return null;
      }
      latitude = lat;
      longitude = lng;
    }

    setState(() => _errorMessage = null);
    return (name: name, latitude: latitude, longitude: longitude);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DestinationForm(
            palette: widget.palette,
            nameController: _nameController,
            latController: _latController,
            lngController: _lngController,
            mode: _mode,
            errorMessage: _errorMessage,
            onModeChanged: (mode) => setState(() {
              _mode = mode;
              _errorMessage = null;
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.palette.accent,
                foregroundColor:
                    widget.palette.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Zapisz',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditDestinationDialog extends StatefulWidget {
  const EditDestinationDialog({
    super.key,
    required this.palette,
    required this.destination,
  });

  final AppPalette palette;
  final Destination destination;

  @override
  State<EditDestinationDialog> createState() => _EditDestinationDialogState();
}

class _EditDestinationDialogState extends State<EditDestinationDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.destination.name);
    _latController = TextEditingController(
      text: widget.destination.latitude.toStringAsFixed(6),
    );
    _lngController = TextEditingController(
      text: widget.destination.longitude.toStringAsFixed(6),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Podaj nazwę miejsca.');
      return;
    }

    final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      setState(() => _errorMessage = 'Wpisz poprawne współrzędne.');
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _errorMessage = 'Współrzędne są poza dozwolonym zakresem.');
      return;
    }

    Navigator.pop(
      context,
      _EditResult(
        updated: widget.destination.copyWith(
          name: name,
          latitude: lat,
          longitude: lng,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.palette.dialogBackground,
        title: Text(
          'Usunąć miejsce?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: widget.palette.textPrimary,
          ),
        ),
        content: Text(
          'Czy na pewno usunąć „${widget.destination.name}"?',
          style: TextStyle(fontSize: 20, color: widget.palette.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Anuluj', style: TextStyle(color: widget.palette.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Usuń', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.pop(context, const _EditResult(deleted: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.palette.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(
        'Edytuj miejsce',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: widget.palette.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StyledTextField(
              palette: widget.palette,
              controller: _nameController,
              label: 'Nazwa miejsca',
            ),
            const SizedBox(height: 16),
            _StyledTextField(
              palette: widget.palette,
              controller: _latController,
              label: 'Szerokość geograficzna',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
            ),
            const SizedBox(height: 12),
            _StyledTextField(
              palette: widget.palette,
              controller: _lngController,
              label: 'Długość geograficzna',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 18, color: Colors.red.shade400),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              label: Text(
                'Usuń to miejsce',
                style: TextStyle(fontSize: 18, color: Colors.red.shade400),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Anuluj', style: TextStyle(fontSize: 20, color: widget.palette.accent)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('Zapisz', style: TextStyle(fontSize: 20, color: widget.palette.accent)),
        ),
      ],
    );
  }
}

class _DestinationForm extends StatelessWidget {
  const _DestinationForm({
    required this.palette,
    required this.nameController,
    required this.latController,
    required this.lngController,
    required this.mode,
    required this.errorMessage,
    required this.onModeChanged,
  });

  final AppPalette palette;
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final _AddMode mode;
  final String? errorMessage;
  final ValueChanged<_AddMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StyledTextField(
          palette: palette,
          controller: nameController,
          label: 'Nazwa miejsca',
        ),
        const SizedBox(height: 20),
        _ModeButton(
          palette: palette,
          label: 'Zapisz tutaj, gdzie stoję',
          icon: Icons.my_location,
          selected: mode == _AddMode.currentGps,
          onTap: () => onModeChanged(_AddMode.currentGps),
        ),
        const SizedBox(height: 12),
        _ModeButton(
          palette: palette,
          label: 'Wpisz współrzędne ręcznie',
          icon: Icons.edit_location_alt,
          selected: mode == _AddMode.manual,
          onTap: () => onModeChanged(_AddMode.manual),
        ),
        if (mode == _AddMode.manual) ...[
          const SizedBox(height: 16),
          _StyledTextField(
            palette: palette,
            controller: latController,
            label: 'Szerokość (np. 53.444760)',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
            ],
          ),
          const SizedBox(height: 12),
          _StyledTextField(
            palette: palette,
            controller: lngController,
            label: 'Długość (np. 14.532817)',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
            ],
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            errorMessage!,
            style: TextStyle(fontSize: 18, color: Colors.red.shade400),
          ),
        ],
      ],
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.palette,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
  });

  final AppPalette palette;
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(fontSize: 20, color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 18, color: palette.textSecondary),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.surfaceBorder),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.palette,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final IconData icon;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.surfaceBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ekran kompasu
// ---------------------------------------------------------------------------

class CompassScreen extends StatefulWidget {
  const CompassScreen({
    super.key,
    required this.settings,
    required this.destination,
  });

  final AppSettings settings;
  final Destination destination;

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  Position? _currentPosition;
  double? _deviceHeading;
  String? _errorMessage;
  bool _permissionGranted = false;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  AppPalette get _palette => widget.settings.palette;

  @override
  void initState() {
    super.initState();
    _initializeSensors();
  }

  Future<void> _initializeSensors() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _errorMessage =
            'Włącz lokalizację GPS w ustawieniach telefonu i uruchom aplikację ponownie.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        _errorMessage =
            'Aplikacja potrzebuje dostępu do lokalizacji, aby pokazać kierunek do celu.';
      });
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _errorMessage =
            'Dostęp do lokalizacji został zablokowany. Włącz go w ustawieniach telefonu.';
      });
      return;
    }

    setState(() {
      _permissionGranted = true;
      _errorMessage = null;
    });

    _startGpsUpdates();
    _startCompassUpdates();
  }

  void _startGpsUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() => _currentPosition = position);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Nie udało się odczytać pozycji GPS. Spróbuj ponownie.';
        });
      },
    );
  }

  void _startCompassUpdates() {
    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (!mounted) return;
        final heading = event.heading;
        if (heading != null) {
          setState(() => _deviceHeading = heading);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Nie udało się odczytać kompasu. Upewnij się, że telefon ma czujnik kierunku.';
        });
      },
    );
  }

  double? _distanceToTarget() {
    if (_currentPosition == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      widget.destination.latitude,
      widget.destination.longitude,
    );
  }

  double? _bearingToTarget() {
    if (_currentPosition == null) return null;
    return Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      widget.destination.latitude,
      widget.destination.longitude,
    );
  }

  double? _arrowRotationDegrees() {
    final bearing = _bearingToTarget();
    final heading = _deviceHeading;
    if (bearing == null || heading == null) return null;

    double rotation = bearing - heading;
    rotation = (rotation + 360) % 360;
    return rotation;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final distance = _distanceToTarget();
        final isAtDestination =
            distance != null && distance <= arrivalRadiusMeters;
        final rotation = _arrowRotationDegrees();

        return Scaffold(
          backgroundColor: _palette.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 28),
                      label: const Text(
                        'Powrót do listy',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _palette.buttonBackground,
                        foregroundColor: _palette.buttonForeground,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.destination.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Expanded(
                    child: _buildBody(
                      isAtDestination: isAtDestination,
                      distance: distance,
                      rotation: rotation,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody({
    required bool isAtDestination,
    required double? distance,
    required double? rotation,
  }) {
    if (_errorMessage != null) {
      return _buildMessageScreen(
        icon: Icons.location_off,
        iconColor: Colors.red.shade400,
        text: _errorMessage!,
      );
    }

    if (!_permissionGranted || _currentPosition == null) {
      return _buildMessageScreen(
        icon: Icons.gps_fixed,
        iconColor: _palette.accent,
        text: 'Szukam Twojej pozycji GPS...\nTrzymaj telefon w ręku i poczekaj chwilę.',
      );
    }

    if (_deviceHeading == null) {
      return _buildMessageScreen(
        icon: Icons.explore,
        iconColor: _palette.accent,
        text: 'Kalibruję kompas...\nObróć telefon w kształcie ósemki.',
      );
    }

    if (isAtDestination) {
      return _buildArrivedScreen();
    }

    return _buildNavigationScreen(distance: distance, rotation: rotation);
  }

  Widget _buildMessageScreen({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: iconColor),
          const SizedBox(height: 32),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildArrivedScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 200, color: _palette.success),
          const SizedBox(height: 40),
          Text(
            'Jesteś w odległości 5 metrów do celu, rozejrzyj się.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationScreen({
    required double? distance,
    required double? rotation,
  }) {
    final distanceText = distance != null
        ? 'Do celu: ${distance.round()} metrów'
        : 'Obliczam odległość...';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.rotate(
            angle: rotation != null ? rotation * math.pi / 180 : 0,
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 220,
              color: _palette.arrow,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            distanceText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }
}
