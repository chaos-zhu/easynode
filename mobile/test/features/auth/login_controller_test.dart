import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/login_controller.dart';

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
    expect(result.message, '请输入用户名');
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
    expect(result.message, '请输入密码');
  });

  test('returns invalid server address message when normalize throws', () async {
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
    expect(result.message, contains('http'));
  });
}
