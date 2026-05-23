/// Plaintext SSH connection parameters returned by `/mobile/ssh-connection`
/// after AES-GCM decryption. Mirrors `toMobileSshPayload` on the server.
class SshConnectionConfig {
  const SshConnectionConfig({
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

  factory SshConnectionConfig.fromJson(Map<String, dynamic> json) {
    final portRaw = json['port'];
    final int port;
    if (portRaw is int) {
      port = portRaw;
    } else if (portRaw is num) {
      port = portRaw.toInt();
    } else {
      port = int.tryParse(portRaw?.toString() ?? '') ?? 22;
    }
    return SshConnectionConfig(
      hostId: (json['hostId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: port,
      username: (json['username'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      privateKey: (json['privateKey'] ?? '').toString(),
      passphrase: (json['passphrase'] ?? '').toString(),
    );
  }
}
