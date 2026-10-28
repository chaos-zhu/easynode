import '../../core/ai/agent_mode.dart';

class ServerAiPolicy {
  const ServerAiPolicy({
    this.enabled = true,
    this.maxEffect = 'write',
    this.maxMode = defaultAgentHostMode,
  });

  final bool enabled;
  final String maxEffect;
  final String maxMode;

  factory ServerAiPolicy.fromJson(Object? value) {
    final json = value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final effect = json['maxEffect']?.toString();
    final mode = json['maxMode']?.toString();
    return ServerAiPolicy(
      enabled: json['enabled'] != false,
      maxEffect: const {'read', 'write'}.contains(effect) ? effect! : 'write',
      maxMode: normalizeAgentMode(mode ?? defaultAgentHostMode),
    );
  }
}

/// Native-side projection of `/api/v1/host-catalog` items.
///
/// Only fields needed for the native list and connect action are kept;
/// passwords, private keys, etc. are intentionally excluded — the server
/// also clears them in its catalog response.
class ServerModel {
  const ServerModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    this.credential,
    required this.connectType,
    required this.group,
    required this.proxyType,
    required this.jumpHosts,
    required this.proxyServer,
    required this.tag,
    required this.expiredAt,
    required this.expiredNotify,
    required this.consoleUrl,
    required this.command,
    required this.expired,
    required this.isConfig,
    required this.aiPolicy,
    this.lastConnectTime,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String? credential;
  final String connectType;
  final String group;
  final String proxyType;
  final List<String> jumpHosts;
  final String proxyServer;
  final List<String> tag;
  final DateTime? expiredAt;
  final bool expiredNotify;
  final String consoleUrl;
  final String command;
  final bool expired;
  final bool isConfig;
  final ServerAiPolicy aiPolicy;
  final DateTime? lastConnectTime;

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['_id'] ?? '').toString();
    final tagRaw = json['tag'];
    final jumpHostsRaw = json['jumpHosts'];
    final List<String> tag;
    if (tagRaw is List) {
      tag = tagRaw.map((e) => e.toString()).toList(growable: false);
    } else {
      tag = const [];
    }
    final List<String> jumpHosts;
    if (jumpHostsRaw is List) {
      jumpHosts = jumpHostsRaw.map((e) => e.toString()).toList(growable: false);
    } else {
      jumpHosts = const [];
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
      credential: (json['credential'] ?? '').toString(),
      connectType: (json['connectType'] ?? '').toString(),
      group: (json['group'] ?? '').toString(),
      proxyType: (json['proxyType'] ?? '').toString(),
      jumpHosts: jumpHosts,
      proxyServer: (json['proxyServer'] ?? '').toString(),
      tag: tag,
      expiredAt: _parseDate(json['expired']),
      expiredNotify: json['expiredNotify'] == true,
      consoleUrl: (json['consoleUrl'] ?? '').toString(),
      command: (json['command'] ?? '').toString(),
      expired: json['expired'] == true,
      isConfig: json['isConfig'] == true,
      aiPolicy: ServerAiPolicy.fromJson(json['aiPolicy']),
      lastConnectTime: _parseDate(json['lastConnectTime']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null || value == false || value == true) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final text = value.toString();
    final timestamp = int.tryParse(text);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return DateTime.tryParse(text);
  }

  /// Whether the connect button should be enabled. The server marks hosts
  /// without auth fields as `isConfig: false`.
  bool get canConnect => isConfig;
  bool get isWindows => connectType == 'rdp';

  String get displayName => name.isEmpty ? host : name;
  String get connectionLabel => '$username@$host:$port';
}
