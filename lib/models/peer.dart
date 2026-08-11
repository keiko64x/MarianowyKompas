class Peer {
  const Peer({
    required this.userId,
    required this.name,
    required this.displayName,
    this.lastSeenAt,
    this.lastActivityLabel = 'Brak aktywności',
    this.hasLocation = false,
    this.cachedLatitude,
    this.cachedLongitude,
    this.cachedAt,
  });

  final String userId;
  final String name;
  final String displayName;
  final String? lastSeenAt;
  final String lastActivityLabel;
  final bool hasLocation;
  final double? cachedLatitude;
  final double? cachedLongitude;
  final DateTime? cachedAt;

  Peer copyWith({
    String? displayName,
    String? lastSeenAt,
    String? lastActivityLabel,
    bool? hasLocation,
    double? cachedLatitude,
    double? cachedLongitude,
    DateTime? cachedAt,
  }) {
    return Peer(
      userId: userId,
      name: name,
      displayName: displayName ?? this.displayName,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastActivityLabel: lastActivityLabel ?? this.lastActivityLabel,
      hasLocation: hasLocation ?? this.hasLocation,
      cachedLatitude: cachedLatitude ?? this.cachedLatitude,
      cachedLongitude: cachedLongitude ?? this.cachedLongitude,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'displayName': displayName,
        'lastSeenAt': lastSeenAt,
        'lastActivityLabel': lastActivityLabel,
        'hasLocation': hasLocation,
        'cachedLatitude': cachedLatitude,
        'cachedLongitude': cachedLongitude,
        'cachedAt': cachedAt?.toIso8601String(),
      };

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      userId: json['userId'] as String,
      name: (json['name'] as String?) ?? 'Osoba',
      displayName: (json['displayName'] as String?) ??
          (json['name'] as String?) ??
          'Osoba',
      lastSeenAt: json['lastSeenAt'] as String?,
      lastActivityLabel:
          (json['lastActivityLabel'] as String?) ?? 'Brak aktywności',
      hasLocation: json['hasLocation'] as bool? ?? false,
      cachedLatitude: (json['cachedLatitude'] as num?)?.toDouble(),
      cachedLongitude: (json['cachedLongitude'] as num?)?.toDouble(),
      cachedAt: json['cachedAt'] != null
          ? DateTime.tryParse(json['cachedAt'] as String)
          : null,
    );
  }
}

class PeerLocation {
  const PeerLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.timestamp,
    this.fetchedAt,
    this.lastActivityLabel,
    this.etag,
  });

  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  /// meters/second when known
  final double? speed;
  /// degrees clockwise from north when known
  final double? heading;
  final DateTime? timestamp;
  final DateTime? fetchedAt;
  final String? lastActivityLabel;
  final String? etag;

  factory PeerLocation.fromJson(Map<String, dynamic> json, {String? etag}) {
    final ts = json['timestamp'] ?? json['t'];
    final acc = json['accuracy'] ?? json['acc'];
    final spd = json['speed'] ?? json['spd'];
    final hdg = json['heading'] ?? json['hdg'];
    return PeerLocation(
      userId: json['userId'] as String? ?? '',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      accuracy: (acc as num?)?.toDouble(),
      speed: (spd as num?)?.toDouble(),
      heading: (hdg as num?)?.toDouble(),
      timestamp: ts != null ? DateTime.tryParse(ts as String) : null,
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.tryParse(json['fetchedAt'] as String)
          : DateTime.now(),
      lastActivityLabel: json['lastActivityLabel'] as String?,
      etag: etag ?? (ts is String ? ts : null),
    );
  }
}

class PairRequest {
  const PairRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    this.fromName,
    this.createdAt,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String? fromName;
  final String? createdAt;

  factory PairRequest.fromJson(Map<String, dynamic> json) {
    final fromUser = json['fromUser'] as Map<String, dynamic>?;
    return PairRequest(
      id: json['id'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      fromName: fromUser?['name'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
