import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/http_proxy_connector.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';
import 'package:mobile/features/terminal/ssh_transport.dart';

void main() {
  const directConfig = SshConnectionConfig(
    hostId: 'h1',
    name: 'prod',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret',
    privateKey: '',
    passphrase: '',
    proxyType: '',
    proxy: null,
    jumpHosts: [],
  );

  test('opens direct socket when proxyType is empty', () async {
    final opened = <String>[];
    final factory = SshTransportFactory(
      connectSocket: (host, port) async {
        opened.add('$host:$port');
        return FakeSocket(host);
      },
    );

    final handle = await factory.open(directConfig);

    expect(opened, ['10.0.0.2:22']);
    expect(handle.socket, isA<FakeSocket>());
  });

  test('fails explicitly for unsupported proxy type', () async {
    final factory = SshTransportFactory(
      connectSocket: (host, port) async => FakeSocket(host),
    );
    const proxiedConfig = SshConnectionConfig(
      hostId: 'h1',
      name: 'prod',
      host: '10.0.0.2',
      port: 22,
      username: 'root',
      authType: 'password',
      password: 'secret',
      privateKey: '',
      passphrase: '',
      proxyType: 'http',
      proxy: null,
      jumpHosts: [],
    );

    expect(
      () => factory.open(proxiedConfig),
      throwsA(
        isA<SshTransportException>().having(
          (error) => error.message,
          'message',
          'Unsupported mobile proxy type: http',
        ),
      ),
    );
  });

  test('opens http proxy socket when proxy type is http', () async {
    final logs = <String>[];
    final factory = SshTransportFactory(
      connectSocket: (host, port) async => FakeSocket('unused'),
      httpProxyConnector: FakeHttpProxyConnector(FakeSocket('http-tunnel')),
    );
    const proxiedConfig = SshConnectionConfig(
      hostId: 'h1',
      name: 'prod',
      host: '10.0.0.2',
      port: 22,
      username: 'root',
      authType: 'password',
      password: 'secret',
      privateKey: '',
      passphrase: '',
      proxyType: 'proxyServer',
      proxy: SshProxyConfig(
        id: 'p1',
        name: 'office',
        type: 'http',
        host: '127.0.0.1',
        port: 8080,
        username: 'u',
        password: 'p',
      ),
      jumpHosts: [],
    );

    final handle = await factory.open(proxiedConfig, logger: logs.add);

    expect(handle.socket, isA<FakeSocket>());
    expect((handle.socket as FakeSocket).label, 'http-tunnel');
    expect(logs, [
      '使用代理服务器 office (HTTP) - 127.0.0.1:8080',
      '代理连接建立成功，准备通过代理连接目标服务器',
    ]);
  });

  test('fails when jumpHosts proxyType has empty chain', () async {
    final factory = SshTransportFactory(
      connectSocket: (host, port) async => FakeSocket('unused'),
    );
    const jumpConfig = SshConnectionConfig(
      hostId: 'h1',
      name: 'prod',
      host: '10.0.0.2',
      port: 22,
      username: 'root',
      authType: 'password',
      password: 'secret',
      privateKey: '',
      passphrase: '',
      proxyType: 'jumpHosts',
      proxy: null,
      jumpHosts: [],
    );

    expect(
      () => factory.open(jumpConfig),
      throwsA(
        isA<SshTransportException>().having(
          (error) => error.message,
          'message',
          'Jump host connection failed: empty chain',
        ),
      ),
    );
  });

  test('opens jump host chain and keeps intermediate clients', () async {
    final opened = <String>[];
    final closed = <String>[];
    final logs = <String>[];
    final factory = SshTransportFactory(
      connectSocket: (host, port) async {
        opened.add('tcp:$host:$port');
        return FakeSocket(host);
      },
      createClient: (socket, auth) => FakeSshClient(
        auth.host,
        closed,
        forwardSocket: FakeSocket('forward:${auth.host}'),
      ),
    );
    const jumpConfig = SshConnectionConfig(
      hostId: 'h1',
      name: 'prod',
      host: '10.0.0.2',
      port: 22,
      username: 'root',
      authType: 'password',
      password: 'secret',
      privateKey: '',
      passphrase: '',
      proxyType: 'jumpHosts',
      proxy: null,
      jumpHosts: [
        SshJumpHostConfig(
          hostId: 'j1',
          name: 'jump',
          host: '203.0.113.10',
          port: 22,
          username: 'root',
          authType: 'password',
          password: 'jump-secret',
          privateKey: '',
          passphrase: '',
        ),
      ],
    );

    final handle = await factory.open(jumpConfig, logger: logs.add);

    expect(opened, ['tcp:203.0.113.10:22']);
    expect(handle.socket, isA<FakeSocket>());
    expect(logs, [
      '准备通过跳板机连接目标服务器，共 1 跳',
      '连接跳板机 1/1: jump - 203.0.113.10:22',
      '跳板机认证成功: jump',
      '跳板机转发: 203.0.113.10:22 -> 10.0.0.2:22',
      '跳板机连接成功，准备连接目标服务器',
    ]);
    await handle.close();
    expect(closed, ['203.0.113.10']);
  });
}

class FakeHttpProxyConnector extends HttpProxyConnector {
  FakeHttpProxyConnector(this.socket);

  final SSHSocket socket;

  @override
  Future<SSHSocket> connect({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String username = '',
    String password = '',
  }) async {
    return socket;
  }
}

class FakeSshClient implements SshClientHandle {
  FakeSshClient(this.label, this.closed, {required this.forwardSocket});

  final String label;
  final List<String> closed;
  final SSHSocket forwardSocket;

  @override
  Future<void> get authenticated async {}

  @override
  Future<SSHSocket> forwardLocal(String host, int port) async => forwardSocket;

  @override
  void close() {
    closed.add(label);
  }
}

class FakeSocket implements SSHSocket {
  FakeSocket(this.label);

  final String label;
  bool closed = false;
  final _controller = StreamController<Uint8List>();
  final _sinkController = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  StreamSink<List<int>> get sink => _sinkController.sink;

  @override
  Future<void> get done => _controller.done;

  @override
  Future<void> close() async {
    closed = true;
    unawaited(_sinkController.close());
    unawaited(_controller.close());
  }

  @override
  void destroy() {
    closed = true;
    unawaited(_sinkController.close());
    unawaited(_controller.close());
  }
}
