class UserProfile {
  const UserProfile({
    required this.userId,
    required this.deviceToken,
    required this.name,
  });

  final String userId;
  final String deviceToken;
  final String name;

  UserProfile copyWith({String? name}) {
    return UserProfile(
      userId: userId,
      deviceToken: deviceToken,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'deviceToken': deviceToken,
        'name': name,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String,
      deviceToken: json['deviceToken'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Użytkownik',
    );
  }

  /// Payload kodu QR udostępniającego profil.
  String toQrPayload() =>
      '{"v":1,"userId":"$userId","name":${_jsonString(name)}}';

  static String _jsonString(String value) {
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}
