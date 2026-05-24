/// Proxy record returned by `GET /proxy`. Web returns passwords plaintext but
/// we never display them — UI masks with bullets. Add/update bodies POST the
/// full object to `/proxy` (POST for create, PUT `/proxy/:id` for update).
class ServerProxyModel {
  const ServerProxyModel({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.createTime,
    this.updateTime,
  });

  final String id;
  final String name;
  final String type;
  final String host;
  final int port;
  final String username;
  final String password;
  final int? createTime;
  final int? updateTime;

  factory ServerProxyModel.fromJson(Map<String, dynamic> json) {
    final portRaw = json['port'];
    int port = 0;
    if (portRaw is int) {
      port = portRaw;
    } else if (portRaw is num) {
      port = portRaw.toInt();
    } else if (portRaw is String) {
      port = int.tryParse(portRaw) ?? 0;
    }
    int? parseTime(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    }

    return ServerProxyModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: port,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      createTime: parseTime(json['createTime']),
      updateTime: parseTime(json['updateTime']),
    );
  }

  String get displayName => name.isEmpty ? id : name;
  String get typeLabel => type.isEmpty ? 'SOCKS' : type.toUpperCase();
  String get endpoint => host.isEmpty ? '' : '$host:$port';
}
