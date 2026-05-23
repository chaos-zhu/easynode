import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';

void main() {
  SshConnectionConfig configWithPassphrase(String passphrase) {
    return SshConnectionConfig(
      hostId: 'h1',
      name: 'prod',
      host: '10.0.0.2',
      port: 22,
      username: 'root',
      authType: 'privateKey',
      password: '',
      privateKey: 'key',
      passphrase: passphrase,
    );
  }

  test('uses null passphrase for unencrypted private keys', () {
    expect(configWithPassphrase('').privateKeyPassphrase, isNull);
    expect(configWithPassphrase('   ').privateKeyPassphrase, isNull);
  });

  test('keeps non-empty private key passphrase', () {
    expect(configWithPassphrase(' secret ').privateKeyPassphrase, 'secret');
  });
}
