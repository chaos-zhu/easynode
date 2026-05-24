/// One entry of `GET /log` -> `data.list`. The server sends a parsed
/// user-agent in `agentInfo`, plus geolocation strings (country / city).
/// `revoked == 1` is the truthy marker.
class LoginSession {
  const LoginSession({
    required this.id,
    required this.deviceId,
    required this.tokenHash,
    required this.userId,
    required this.revoked,
    required this.ip,
    required this.country,
    required this.city,
    required this.browser,
    required this.os,
    required this.createAt,
    required this.expireAt,
  });

  final String id;
  final String deviceId;
  final String tokenHash;
  final String userId;
  final bool revoked;
  final String ip;
  final String country;
  final String city;
  final String browser;
  final String os;
  final int createAt;
  final int expireAt;

  bool get isMobile =>
      browser.contains('EasyNode-Mobile') || os.contains('EasyNode-Mobile');

  String get location {
    final parts = <String>[
      if (country.isNotEmpty) country,
      if (city.isNotEmpty) city,
    ];
    return parts.join(' · ');
  }

  String get agentLabel {
    final parts = <String>[];
    if (browser.isNotEmpty) parts.add(browser);
    if (os.isNotEmpty) parts.add(os);
    return parts.join(' · ');
  }

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    int parseTime(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? 0;
      return 0;
    }

    final agent = json['agentInfo'];
    String browser = '';
    String os = '';
    if (agent is Map) {
      final browserInfo = agent['browser'];
      final osInfo = agent['os'];
      if (browserInfo is Map) {
        final name = (browserInfo['name'] ?? '').toString();
        final version = (browserInfo['version'] ?? '').toString();
        browser = version.isEmpty ? name : '$name $version';
      }
      if (osInfo is Map) {
        final name = (osInfo['name'] ?? '').toString();
        final version = (osInfo['version'] ?? '').toString();
        os = version.isEmpty ? name : '$name $version';
      }
    }

    final revokedRaw = json['revoked'];
    final revoked = revokedRaw == 1 ||
        revokedRaw == true ||
        revokedRaw == '1' ||
        revokedRaw == 'true';

    return LoginSession(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      tokenHash: (json['tokenHash'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      revoked: revoked,
      ip: (json['ip'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      browser: browser,
      os: os,
      createAt: parseTime(json['create']),
      expireAt: parseTime(json['expireAt']),
    );
  }
}

/// `GET /log` -> `data` shape: `{ list, ipWhiteList }`.
class LoginLogData {
  const LoginLogData({required this.sessions, required this.ipWhiteList});

  final List<LoginSession> sessions;
  final List<String> ipWhiteList;

  factory LoginLogData.fromJson(Map<String, dynamic> json) {
    final list = (json['list'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(LoginSession.fromJson)
            .toList(growable: false) ??
        const <LoginSession>[];
    final whitelist = (json['ipWhiteList'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];
    return LoginLogData(sessions: list, ipWhiteList: whitelist);
  }
}
