import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/crypto/aes_gcm_crypto.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../terminal/ssh_connection_config.dart';

final rdpRepositoryProvider = Provider<RdpRepository>(
  (ref) => RdpRepository(
    ref.watch(apiClientProvider),
    ref.watch(authProvider).publicKeyPem,
  ),
);

/// Uses the same ephemeral RSA/AES envelope as SSH, with a separate server-side
/// RDP type and Plus authorization check. Decrypted credentials are never saved.
class RdpRepository {
  RdpRepository(this.api, this.publicKey);
  final ApiClient api;
  final String? publicKey;

  Future<SshConnectionConfig> fetch(String hostId) async {
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    try {
      final response = await api.postJson('/native/rdp-connection', {
        'hostId': hostId,
        'encryptedKey': RsaCrypto().encryptTemporaryKey(
          publicKey ?? await api.getPublicKey(),
          key,
        ),
      });
      if (response['status'] != 200) {
        throw ApiFailure(
          response['msg']?.toString() ?? 'RDP connection failed',
        );
      }
      final data = response['data'];
      if (data is! Map ||
          data['alg'] != 'AES-256-GCM' ||
          data['iv'] is! String ||
          data['tag'] is! String ||
          data['ciphertext'] is! String) {
        throw const FormatException('Invalid encrypted RDP response');
      }
      final config = SshConnectionConfig.fromJson(
        decryptAesGcmJson(
          key: key,
          ivBase64: data['iv'],
          tagBase64: data['tag'],
          ciphertextBase64: data['ciphertext'],
        ),
      );
      if (config.hostId != hostId ||
          config.host.isEmpty ||
          config.username.isEmpty ||
          config.authType != 'password' ||
          config.port < 1 ||
          config.port > 65535) {
        throw const FormatException('Invalid RDP connection parameters');
      }
      return config;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
