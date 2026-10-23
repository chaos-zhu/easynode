import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/features/rdp/rdp_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

class _EncryptedApi extends ApiClient {
  _EncryptedApi(this.publicKey, this.privateKey)
    : super(
        serverAddress: 'https://panel.example.com',
        cookieStore: SessionCookieStore.memory(),
      );
  final String publicKey;
  final RSAPrivateKey privateKey;
  bool plus = true, tamper = false;
  String returnedHostId = 'windows-1';
  final keys = <String>[];
  @override
  Future<String> getPublicKey() async => publicKey;
  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    expect(path, '/native/rdp-connection');
    expect(data['hostId'], 'windows-1');
    expect(data.keys.toSet(), {'hostId', 'encryptedKey'});
    if (!plus) return {'status': 400, 'msg': 'RDP requires Plus'};
    final rsa = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final key = base64Decode(
      utf8.decode(rsa.process(base64Decode(data['encryptedKey']))),
    );
    keys.add(base64Encode(key));
    final iv = Uint8List.fromList(List.generate(12, (i) => i));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final encrypted = cipher.process(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'hostId': returnedHostId,
            'host': '10.0.0.2',
            'port': 3389,
            'username': 'DOMAIN\\user',
            'authType': 'password',
            'password': 'remote-secret',
            'proxyType': 'jumpHosts',
            'jumpHosts': [
              {
                'hostId': 'jump-1',
                'host': '10.0.0.1',
                'port': 22,
                'username': 'jump',
                'authType': 'privateKey',
                'privateKey': 'jump-key',
              },
            ],
          }),
        ),
      ),
    );
    if (tamper) encrypted[0] ^= 1;
    return {
      'status': 200,
      'data': {
        'alg': 'AES-256-GCM',
        'iv': base64Encode(iv),
        'tag': base64Encode(encrypted.sublist(encrypted.length - 16)),
        'ciphertext': base64Encode(encrypted.sublist(0, encrypted.length - 16)),
      },
    };
  }
}

void main() {
  late _EncryptedApi api;
  setUp(() {
    final pair = CryptoUtils.generateRSAKeyPair();
    api = _EncryptedApi(
      CryptoUtils.encodeRSAPublicKeyToPem(pair.publicKey as RSAPublicKey),
      pair.privateKey as RSAPrivateKey,
    );
  });
  tearDown(() => api.close());
  test(
    'decrypts an authorized local RDP connection including its jump topology with a fresh key each time',
    () async {
      final repository = RdpRepository(api, null);
      final config = await repository.fetch('windows-1');
      expect(config.password, 'remote-secret');
      expect(config.port, 3389);
      expect(config.username, 'DOMAIN\\user');
      expect(config.jumpHosts.single.privateKey, 'jump-key');
      await repository.fetch('windows-1');
      expect(api.keys.toSet().length, 2);
    },
  );
  test(
    'rejects Plus denial, changed ciphertext and a mismatched host instead of using SSH or guacd',
    () async {
      final repository = RdpRepository(api, api.publicKey);
      api.plus = false;
      await expectLater(
        repository.fetch('windows-1'),
        throwsA(isA<ApiFailure>()),
      );
      api.plus = true;
      api.tamper = true;
      await expectLater(repository.fetch('windows-1'), throwsA(anything));
      api.tamper = false;
      api.returnedHostId = 'other';
      await expectLater(repository.fetch('windows-1'), throwsFormatException);
    },
  );
}
