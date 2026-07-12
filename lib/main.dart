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
const String _storageKey = 'custom_destinations';

const Destination builtInDestination = Destination(
  id: 'built_in_cemetery_gate',
  name: 'Brama Główna Cmentarza',
  latitude: 53.4199,
  longitude: 14.5242,
  isBuiltIn: true,
);

// ---------------------------------------------------------------------------
// Aplikacja
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MarianowyKompasApp());
}

class MarianowyKompasApp extends StatelessWidget {
  const MarianowyKompasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marianowy Kompas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          headlineMedium: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ),
      home: const PlacesListScreen(),
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
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final bool isBuiltIn;

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
// Lokalna baza miejsc (shared_preferences + JSON)
// ---------------------------------------------------------------------------

class DestinationStorage {
  Future<List<Destination>> loadCustomDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Destination.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCustomDestinations(List<Destination> destinations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(destinations.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> addDestination(Destination destination) async {
    final current = await loadCustomDestinations();
    current.add(destination);
    await saveCustomDestinations(current);
  }

  Future<void> removeDestination(String id) async {
    final current = await loadCustomDestinations();
    current.removeWhere((d) => d.id == id);
    await saveCustomDestinations(current);
  }
}

// ---------------------------------------------------------------------------
// Ekran listy miejsc (startowy)
// ---------------------------------------------------------------------------

class PlacesListScreen extends StatefulWidget {
  const PlacesListScreen({super.key});

  @override
  State<PlacesListScreen> createState() => _PlacesListScreenState();
}

class _PlacesListScreenState extends State<PlacesListScreen> {
  final DestinationStorage _storage = DestinationStorage();
  List<Destination> _customDestinations = [];
  Position? _currentPosition;
  String? _gpsStatusMessage;

  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _initializeGps();
  }

  Future<void> _loadDestinations() async {
    final saved = await _storage.loadCustomDestinations();
    if (!mounted) return;
    setState(() => _customDestinations = saved);
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

  List<Destination> get _allDestinations => [
        builtInDestination,
        ..._customDestinations,
      ];

  Future<void> _openAddDialog() async {
    final result = await showDialog<Destination>(
      context: context,
      builder: (context) => AddDestinationDialog(
        currentPosition: _currentPosition,
      ),
    );

    if (result == null) return;
    await _storage.addDestination(result);
    await _loadDestinations();
  }

  Future<void> _confirmDelete(Destination destination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Usunąć miejsce?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Czy na pewno usunąć „${destination.name}"?',
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Usuń',
              style: TextStyle(fontSize: 20, color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _storage.removeDestination(destination.id);
    await _loadDestinations();
  }

  void _openCompass(Destination destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompassScreen(destination: destination),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Miejsca docelowe',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _allDestinations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final destination = _allDestinations[index];
                  return _DestinationTile(
                    destination: destination,
                    onTap: () => _openCompass(destination),
                    onDelete: destination.isBuiltIn
                        ? null
                        : () => _confirmDelete(destination),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _openAddDialog,
                  icon: const Icon(Icons.add_location_alt, size: 32),
                  label: const Text(
                    'Dodaj nowe miejsce',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            _CurrentGpsBar(
              position: _currentPosition,
              statusMessage: _gpsStatusMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.destination,
    required this.onTap,
    this.onDelete,
  });

  final Destination destination;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              Icon(
                Icons.place,
                size: 36,
                color: Colors.blue.shade800,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  destination.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 32,
                    color: Colors.red.shade700,
                  ),
                  tooltip: 'Usuń',
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
    required this.position,
    required this.statusMessage,
  });

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
      color: Colors.grey.shade200,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog dodawania nowego miejsca
// ---------------------------------------------------------------------------

enum _AddMode { currentGps, manual }

class AddDestinationDialog extends StatefulWidget {
  const AddDestinationDialog({
    super.key,
    required this.currentPosition,
  });

  final Position? currentPosition;

  @override
  State<AddDestinationDialog> createState() => _AddDestinationDialogState();
}

class _AddDestinationDialogState extends State<AddDestinationDialog> {
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Podaj nazwę miejsca.');
      return;
    }

    double latitude;
    double longitude;

    if (_mode == _AddMode.currentGps) {
      final position = widget.currentPosition;
      if (position == null) {
        setState(() => _errorMessage = 'Nie mam jeszcze pozycji GPS. Poczekaj chwilę.');
        return;
      }
      latitude = position.latitude;
      longitude = position.longitude;
    } else {
      final lat = double.tryParse(_latController.text.replaceAll(',', '.'));
      final lng = double.tryParse(_lngController.text.replaceAll(',', '.'));
      if (lat == null || lng == null) {
        setState(() => _errorMessage = 'Wpisz poprawne współrzędne (np. 53.4199).');
        return;
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        setState(() => _errorMessage = 'Współrzędne są poza dozwolonym zakresem.');
        return;
      }
      latitude = lat;
      longitude = lng;
    }

    final destination = Destination(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      latitude: latitude,
      longitude: longitude,
    );

    Navigator.pop(context, destination);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: const Text(
        'Dodaj nowe miejsce',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: 'Nazwa miejsca',
                labelStyle: TextStyle(fontSize: 18),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _ModeButton(
              label: 'Zapisz tutaj, gdzie stoję',
              icon: Icons.my_location,
              selected: _mode == _AddMode.currentGps,
              onTap: () => setState(() {
                _mode = _AddMode.currentGps;
                _errorMessage = null;
              }),
            ),
            const SizedBox(height: 12),
            _ModeButton(
              label: 'Wpisz współrzędne ręcznie',
              icon: Icons.edit_location_alt,
              selected: _mode == _AddMode.manual,
              onTap: () => setState(() {
                _mode = _AddMode.manual;
                _errorMessage = null;
              }),
            ),
            if (_mode == _AddMode.manual) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _latController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                ],
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Szerokość (np. 53.4199)',
                  labelStyle: TextStyle(fontSize: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lngController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                ],
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Długość (np. 14.5242)',
                  labelStyle: TextStyle(fontSize: 18),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 18, color: Colors.red.shade700),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj', style: TextStyle(fontSize: 20)),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Zapisz', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.blue.shade50 : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.blue.shade800 : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: Colors.blue.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
// Ekran kompasu / nawigacji strzałką
// ---------------------------------------------------------------------------

class CompassScreen extends StatefulWidget {
  const CompassScreen({
    super.key,
    required this.destination,
  });

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
    final distance = _distanceToTarget();
    final isAtDestination =
        distance != null && distance <= arrivalRadiusMeters;
    final rotation = _arrowRotationDegrees();

    return Scaffold(
      backgroundColor: Colors.white,
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
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black,
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
  }

  Widget _buildBody({
    required bool isAtDestination,
    required double? distance,
    required double? rotation,
  }) {
    if (_errorMessage != null) {
      return _buildMessageScreen(
        icon: Icons.location_off,
        iconColor: Colors.red.shade700,
        text: _errorMessage!,
      );
    }

    if (!_permissionGranted || _currentPosition == null) {
      return _buildMessageScreen(
        icon: Icons.gps_fixed,
        iconColor: Colors.blue.shade700,
        text: 'Szukam Twojej pozycji GPS...\nTrzymaj telefon w ręku i poczekaj chwilę.',
      );
    }

    if (_deviceHeading == null) {
      return _buildMessageScreen(
        icon: Icons.explore,
        iconColor: Colors.blue.shade700,
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
          Icon(
            Icons.check_circle,
            size: 200,
            color: Colors.green.shade600,
          ),
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
              color: Colors.blue.shade800,
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
