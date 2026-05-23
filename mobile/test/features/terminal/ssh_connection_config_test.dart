import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';

void main() {
  Map<String, dynamic> basePayload({String passphrase = ''}) => {
    'hostId': 'h1',
    'name': 'prod',
    'host': '10.0.0.2',
    'port': 22,
    'username': 'root',
    'authType': 'privateKey',
    'password': '',
    'privateKey': 'key',
    'passphrase': passphrase,
    'proxyType': '',
    'proxy': null,
    'jumpHosts': [],
  };

  test('parses direct payload and normalizes empty passphrase', () {
    final config = SshConnectionConfig.fromJson(basePayload(passphrase: '   '));

    expect(config.hostId, 'h1');
    expect(config.port, 22);
    expect(config.proxyType, '');
    expect(config.proxy, isNull);
    expect(config.jumpHosts, isEmpty);
    expect(config.privateKeyPassphrase, isNull);
  });

  test('keeps non-empty private key passphrase', () {
    final config = SshConnectionConfig.fromJson(
      basePayload(passphrase: ' secret '),
    );

    expect(config.privateKeyPassphrase, 'secret');
  });

  test('parses socks5 proxy payload', () {
    final config = SshConnectionConfig.fromJson({
      ...basePayload(),
      'proxyType': 'proxyServer',
      'proxy': {
        'id': 'p1',
        'name': 'office',
        'type': 'socks5',
        'host': '127.0.0.1',
        'port': '1080',
        'username': 'u',
        'password': 'p',
      },
    });

    expect(config.proxyType, 'proxyServer');
    expect(config.proxy!.id, 'p1');
    expect(config.proxy!.port, 1080);
    expect(config.proxy!.username, 'u');
  });

  test('parses http proxy payload', () {
    final config = SshConnectionConfig.fromJson({
      ...basePayload(),
      'proxyType': 'proxyServer',
      'proxy': {
        'id': 'p2',
        'name': 'office-http',
        'type': 'http',
        'host': '127.0.0.1',
        'port': '8080',
        'username': 'u',
        'password': 'p',
      },
    });

    expect(config.proxyType, 'proxyServer');
    expect(config.proxy!.type, 'http');
    expect(config.proxy!.port, 8080);
  });

  test('parses jump host payload and normalizes jump passphrase', () {
    final config = SshConnectionConfig.fromJson({
      ...basePayload(),
      'proxyType': 'jumpHosts',
      'jumpHosts': [
        {
          'hostId': 'j1',
          'name': 'jump',
          'host': '203.0.113.10',
          'port': 2200,
          'username': 'root',
          'authType': 'privateKey',
          'password': '',
          'privateKey': 'jump-key',
          'passphrase': '',
        },
      ],
    });

    expect(config.jumpHosts, hasLength(1));
    expect(config.jumpHosts.single.hostId, 'j1');
    expect(config.jumpHosts.single.port, 2200);
    expect(config.jumpHosts.single.privateKeyPassphrase, isNull);
  });
}
