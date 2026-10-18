import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

class _EnvelopeApi extends ApiClient {
  _EnvelopeApi(this.publicPem, this.privateKey)
    : super(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  final String publicPem;
  final RSAPrivateKey privateKey;
  bool offline = true;
  int writes = 0;

  @override
  Future<String> getPublicKey() async {
    if (offline) throw ApiFailure('unreachable');
    return publicPem;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    expect(path, '/native/ssh-connection');
    expect(data['hostId'], 'host-1');
    writes++;
    // Mirror the server's PKCS1 -> base64 AES key -> GCM response envelope.
    final rsa = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final key = base64Decode(
      utf8.decode(rsa.process(base64Decode(data['encryptedKey'] as String))),
    );
    expect(key, hasLength(32));
    final iv = Uint8List.fromList(List.generate(12, (index) => index));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final encrypted = cipher.process(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'hostId': 'host-1',
            'host': '10.0.0.2',
            'port': 2222,
            'username': 'root',
            'authType': 'password',
            'password': 'ssh-secret',
            'proxyType': 'jumpHosts',
            'jumpHosts': [
              {
                'hostId': 'jump-1',
                'host': '10.0.0.1',
                'port': 22,
                'username': 'jump',
              },
            ],
          }),
        ),
      ),
    );
    return {
      'status': 200,
      'data': {
        'iv': base64Encode(iv),
        'tag': base64Encode(encrypted.sublist(encrypted.length - 16)),
        'ciphertext': base64Encode(encrypted.sublist(0, encrypted.length - 16)),
      },
    };
  }
}

void main() {
  test(
    'restored session retries key loading and decrypts real SSH credentials',
    () async {
      final pair = CryptoUtils.generateRSAKeyPair();
      final api = _EnvelopeApi(
        CryptoUtils.encodeRSAPublicKeyToPem(pair.publicKey as RSAPublicKey),
        pair.privateKey as RSAPrivateKey,
      );
      final repo = ApiServerRepository(apiClient: api);
      await expectLater(
        repo.fetchSshConfig('host-1'),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.writes, 0);
      api.offline = false;
      final config = await repo.fetchSshConfig('host-1');
      expect(config.host, '10.0.0.2');
      expect(config.port, 2222);
      expect(config.password, 'ssh-secret');
      expect(config.proxyType, 'jumpHosts');
      expect(config.jumpHosts.single.host, '10.0.0.1');
    },
  );
}
