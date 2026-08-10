import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/peer.dart';
import '../models/user_profile.dart';

class NetworkException implements Exception {
  NetworkException(this.message, {this.statusCode, this.offline = false});

  final String message;
  final int? statusCode;
  final bool offline;

  @override
  String toString() => message;
}

/// REST client for the home Node.js server (Medicine Compass).
class NetworkService {
  NetworkService({
    this.baseUrl = 'https://server.szadejko.net/api/kompas',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  UserProfile? _profile;

  void setProfile(UserProfile? profile) => _profile = profile;

  Map<String, String> get _authHeaders {
    final profile = _profile;
    if (profile == null) return const {'Content-Type': 'application/json'};
    return {
      'Content-Type': 'application/json',
      'X-User-Id': profile.userId,
      'X-Device-Token': profile.deviceToken,
    };
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  Future<Map<String, dynamic>> _json(
    Future<http.Response> Function() send, {
    Set<int> ok = const {200, 201},
  }) async {
    try {
      final response = await send().timeout(const Duration(seconds: 12));
      Map<String, dynamic> body = {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      }
      if (!ok.contains(response.statusCode)) {
        throw NetworkException(
          body['error']?.toString() ?? 'Błąd serwera (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return body;
    } on TimeoutException {
      throw NetworkException('Brak odpowiedzi serwera (timeout)', offline: true);
    } on http.ClientException catch (e) {
      throw NetworkException('Brak zasięgu sieci: ${e.message}', offline: true);
    } on FormatException {
      throw NetworkException('Nieprawidłowa odpowiedź serwera');
    }
  }

  Future<UserProfile> registerProfile(String name) async {
    final body = await _json(
      () => _client.post(
        _uri('/profile/register'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      ),
      ok: const {200, 201},
    );
    final profile = UserProfile.fromJson(body);
    _profile = profile;
    return profile;
  }

  Future<UserProfile> updateProfileName(String name) async {
    final body = await _json(
      () => _client.patch(
        _uri('/profile'),
        headers: _authHeaders,
        body: jsonEncode({'name': name}),
      ),
    );
    final current = _profile;
    if (current == null) {
      throw NetworkException('Brak lokalnego profilu');
    }
    final updated = current.copyWith(name: body['name'] as String? ?? name);
    _profile = updated;
    return updated;
  }

  Future<List<Peer>> fetchPeers() async {
    final body = await _json(
      () => _client.get(_uri('/peers'), headers: _authHeaders),
    );
    final list = body['peers'] as List<dynamic>? ?? const [];
    return list
        .map((item) => Peer.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<PairRequest>> fetchPendingPairs() async {
    final body = await _json(
      () => _client.get(_uri('/pair/pending'), headers: _authHeaders),
    );
    final list = body['pending'] as List<dynamic>? ?? const [];
    return list
        .map((item) => PairRequest.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> requestPairFromQr(String rawQr) async {
    Object? qrPayload;
    try {
      qrPayload = jsonDecode(rawQr);
    } catch (_) {
      qrPayload = rawQr;
    }
    await _json(
      () => _client.post(
        _uri('/pair/request'),
        headers: _authHeaders,
        body: jsonEncode({'qr': qrPayload}),
      ),
      ok: const {200, 201},
    );
  }

  Future<void> acceptPair(String requestId) async {
    await _json(
      () => _client.post(
        _uri('/pair/accept'),
        headers: _authHeaders,
        body: jsonEncode({'requestId': requestId}),
      ),
    );
  }

  Future<void> rejectPair(String requestId) async {
    await _json(
      () => _client.post(
        _uri('/pair/reject'),
        headers: _authHeaders,
        body: jsonEncode({'requestId': requestId}),
      ),
    );
  }

  Future<void> unpair(String peerUserId) async {
    await _json(
      () => _client.post(
        _uri('/unpair'),
        headers: _authHeaders,
        body: jsonEncode({'peerUserId': peerUserId}),
      ),
    );
  }

  Future<void> renamePeer(String peerUserId, String displayName) async {
    await _json(
      () => _client.patch(
        _uri('/peers/$peerUserId'),
        headers: _authHeaders,
        body: jsonEncode({'displayName': displayName}),
      ),
    );
  }

  Future<void> updateLocation({
    required double lat,
    required double lng,
    double? accuracy,
    DateTime? timestamp,
  }) async {
    await _json(
      () => _client.post(
        _uri('/location/update'),
        headers: _authHeaders,
        body: jsonEncode({
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
          'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
        }),
      ),
    );
  }

  Future<PeerLocation> fetchLocation(String targetUserId) async {
    final body = await _json(
      () => _client.get(
        _uri('/location/$targetUserId'),
        headers: _authHeaders,
      ),
    );
    return PeerLocation.fromJson(body);
  }

  void dispose() => _client.close();
}
