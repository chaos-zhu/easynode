/// Plaintext SSH connection parameters returned by `/mobile/ssh-connection`
/// after AES-GCM decryption. Mirrors `toMobileSshPayload` on the server.
class SshAuthConfig {
  const SshAuthConfig({
    required this.hostId,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.password,
    required this.privateKey,
    required this.passphrase,
  });

  final String hostId;
  final String name;
  final String host;
  final int port;
  final String username;

  /// Either `password` or `privateKey`.
  final String authType;

  /// Only populated when [authType] is `password`.
  final String password;

  /// Only populated when [authType] is `privateKey`.
  final String privateKey;

  /// Optional passphrase for an encrypted private key.
  final String passphrase;

  String? get privateKeyPassphrase {
    final trimmed = passphrase.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static SshAuthConfig fromJson(Map<String, dynamic> json) {
    return SshAuthConfig(
      hostId: (json['hostId'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: _parsePort(json['port']),
      username: (json['username'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      privateKey: (json['privateKey'] ?? '').toString(),
      passphrase: (json['passphrase'] ?? '').toString(),
    );
  }
}

class SshProxyConfig {
  const SshProxyConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String id;
  final String name;
  final String type;
  final String host;
  final int port;
  final String username;
  final String password;

  factory SshProxyConfig.fromJson(Map<String, dynamic> json) {
    return SshProxyConfig(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: _parsePort(json['port']),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }
}

class SshJumpHostConfig extends SshAuthConfig {
  const SshJumpHostConfig({
    required super.hostId,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.authType,
    required super.password,
    required super.privateKey,
    required super.passphrase,
  });

  factory SshJumpHostConfig.fromJson(Map<String, dynamic> json) {
    final auth = SshAuthConfig.fromJson(json);
    return SshJumpHostConfig(
      hostId: auth.hostId,
      name: auth.name,
      host: auth.host,
      port: auth.port,
      username: auth.username,
      authType: auth.authType,
      password: auth.password,
      privateKey: auth.privateKey,
      passphrase: auth.passphrase,
    );
  }
}

class SshConnectionConfig extends SshAuthConfig {
  const SshConnectionConfig({
    required super.hostId,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.authType,
    required super.password,
    required super.privateKey,
    required super.passphrase,
    required this.proxyType,
    required this.proxy,
    required this.jumpHosts,
  });

  final String proxyType;
  final SshProxyConfig? proxy;
  final List<SshJumpHostConfig> jumpHosts;

  factory SshConnectionConfig.fromJson(Map<String, dynamic> json) {
    final auth = SshAuthConfig.fromJson(json);
    final proxyRaw = json['proxy'];
    final jumpHostsRaw = json['jumpHosts'];
    return SshConnectionConfig(
      hostId: auth.hostId,
      name: auth.name,
      host: auth.host,
      port: auth.port,
      username: auth.username,
      authType: auth.authType,
      password: auth.password,
      privateKey: auth.privateKey,
      passphrase: auth.passphrase,
      proxyType: (json['proxyType'] ?? '').toString(),
      proxy: proxyRaw is Map<String, dynamic>
          ? SshProxyConfig.fromJson(proxyRaw)
          : null,
      jumpHosts: jumpHostsRaw is List
          ? jumpHostsRaw
                .whereType<Map<String, dynamic>>()
                .map(SshJumpHostConfig.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

int _parsePort(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 22;
}
