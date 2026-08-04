import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/crypto/rsa_crypto.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/features/auth/login_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _SuccessfulLoginApiClient extends ApiClient {
  _SuccessfulLoginApiClient()
    : super(
        serverAddress: 'https://example.com',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  @override
  Future<String> getPublicKey() async => 'test-public-key';

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    return {
      'status': 200,
      'data': {'token': 'token', 'deviceId': 'device-id'},
    };
  }
}

class _FakeRsaCrypto extends RsaCrypto {
  @override
  String encryptPassword(String publicKeyPem, String plaintext) =>
      'encrypted-password';
}

void main() {
  test('blocks http login until user confirms risk', () async {
    final controller = LoginController.fake();
    final result = await controller.login(
      serverAddress: 'http://127.0.0.1:8082',
      username: 'root',
      password: 'secret',
      mfa2Token: '',
      httpRiskAccepted: false,
      savePassword: false,
    );

    expect(result.requiresHttpRiskConfirmation, isTrue);
    expect(result.success, isFalse);
  });

  test('rejects empty username locally without hitting the api', () async {
    final controller = LoginController.fake();
    final result = await controller.login(
      serverAddress: 'https://example.com',
      username: '   ',
      password: 'secret',
      mfa2Token: '',
      httpRiskAccepted: true,
      savePassword: false,
    );

    expect(result.success, isFalse);
    expect(result.messageKey, 'login.errEmptyUsername');
  });

  test('rejects empty password locally without hitting the api', () async {
    final controller = LoginController.fake();
    final result = await controller.login(
      serverAddress: 'https://example.com',
      username: 'root',
      password: '',
      mfa2Token: '',
      httpRiskAccepted: true,
      savePassword: false,
    );

    expect(result.success, isFalse);
    expect(result.messageKey, 'login.errEmptyPassword');
  });

  test(
    'returns invalid server address message when normalize throws',
    () async {
      final controller = LoginController.fake();
      final result = await controller.login(
        serverAddress: 'ftp://nope',
        username: 'root',
        password: 'secret',
        mfa2Token: '',
        httpRiskAccepted: false,
        savePassword: false,
      );

      expect(result.success, isFalse);
      expect(result.messageKey, 'login.errSchemeUnsupported');
    },
  );

  test('waits for login completion and reports its failure', () async {
    final controller = LoginController(
      apiClientFactory: (_, {String? token}) => _SuccessfulLoginApiClient(),
      rsa: _FakeRsaCrypto(),
    );
    controller.onLoginSuccess((session, passwordToSave) async {
      await Future<void>.delayed(Duration.zero);
      throw ApiFailure('session initialization failed');
    });

    final result = await controller.login(
      serverAddress: 'https://example.com',
      username: 'root',
      password: 'secret',
      mfa2Token: '',
      httpRiskAccepted: true,
      savePassword: false,
    );

    expect(result.success, isFalse);
    expect(result.message, 'session initialization failed');
  });
}
