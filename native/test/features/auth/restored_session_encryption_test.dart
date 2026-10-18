import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/crypto/rsa_crypto.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/servers/server_form_data.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/settings/settings_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  _Api()
    : super(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  bool offline = true;
  final writes = <Map<String, dynamic>>[];

  @override
  Future<String> getPublicKey() async {
    if (offline) throw ApiFailure('Tailscale unavailable');
    return 'recovered-key';
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    writes.add(data);
    return {'status': 200};
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) => postJson(path, data);
}

class _Rsa extends RsaCrypto {
  @override
  String encryptPassword(String publicKeyPem, String plaintext) {
    expect(publicKeyPem, 'recovered-key');
    return 'rsa-wrapped';
  }
}

void main() {
  test(
    'restored server edits retry key loading before sending encrypted secrets',
    () async {
      final api = _Api();
      final repo = ApiServerRepository(apiClient: api, rsa: _Rsa());
      final form = ServerFormData(password: 'ssh-secret');
      await expectLater(repo.createHost(form), throwsA(isA<ApiFailure>()));
      expect(api.writes, isEmpty);
      api.offline = false;
      await repo.createHost(form);
      await repo.updateHost(form);
      for (final body in api.writes) {
        expect(body['password'], isNot('ssh-secret'));
        expect(body['password'], isNotEmpty);
        expect(body['tempKey'], 'rsa-wrapped');
      }
    },
  );

  test(
    'restored account and credential edits load a key before encrypting',
    () async {
      final api = _Api();
      final repo = SettingsRepository(apiClient: api, rsa: _Rsa());
      Future<void> updateAccount() => repo.updateAccount(
        oldLoginName: 'admin',
        oldPwd: 'old-secret',
        newLoginName: 'admin',
        newPwd: 'new-secret',
      );
      await expectLater(updateAccount(), throwsA(isA<ApiFailure>()));
      expect(api.writes, isEmpty);
      api.offline = false;
      await updateAccount();
      expect(api.writes.single['oldPwd'], 'rsa-wrapped');
      expect(api.writes.single['newPwd'], 'rsa-wrapped');
      await repo.createCredential(
        name: 'test',
        authType: 'password',
        password: 'ssh-secret',
      );
      await repo.updateCredential(
        id: 'id',
        name: 'test',
        authType: 'password',
        password: 'ssh-secret',
      );
      for (final body in api.writes.skip(1)) {
        expect(body['password'], isNot('ssh-secret'));
        expect(body['password'], isNotEmpty);
        expect(body['tempKey'], 'rsa-wrapped');
      }
      expect(api.writes.last['id'], 'id');
    },
  );
}
