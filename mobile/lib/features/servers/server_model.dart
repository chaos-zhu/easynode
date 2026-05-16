/// Mobile-side projection of `/api/v1/host-list` items.
///
/// Only fields needed for the mobile list and connect action are kept;
/// passwords, private keys, etc. are intentionally excluded — the server
/// also clears them in its host-list response.
class ServerModel {
  const ServerModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.group,
    required this.tag,
    required this.expired,
    required this.isConfig,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String group;
  final List<String> tag;
  final bool expired;
  final bool isConfig;

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['_id'] ?? '').toString();
    final tagRaw = json['tag'];
    final List<String> tag;
    if (tagRaw is List) {
      tag = tagRaw.map((e) => e.toString()).toList(growable: false);
    } else {
      tag = const [];
    }
    final portRaw = json['port'];
    final int port;
    if (portRaw is int) {
      port = portRaw;
    } else if (portRaw is num) {
      port = portRaw.toInt();
    } else {
      port = int.tryParse(portRaw?.toString() ?? '') ?? 22;
    }
    return ServerModel(
      id: id,
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: port,
      username: (json['username'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      group: (json['group'] ?? '').toString(),
      tag: tag,
      expired: json['expired'] == true,
      isConfig: json['isConfig'] == true,
    );
  }

  /// Whether the connect button should be enabled. The server marks hosts
  /// without auth fields as `isConfig: false`; expired hosts are also not
  /// connectable in the first release.
  bool get canConnect => isConfig && !expired;
}
