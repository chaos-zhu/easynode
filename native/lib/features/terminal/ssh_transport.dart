import 'package:dartssh2/dartssh2.dart';

import 'http_proxy_connector.dart';
import 'socks5_connector.dart';
import 'ssh_connection_config.dart';

typedef SshSocketConnector = Future<SSHSocket> Function(String host, int port);

abstract class SshClientHandle {
  Future<void> get authenticated;
  Future<SSHSocket> forwardLocal(String host, int port);
  void close();
}

typedef SshClientCreator =
    SshClientHandle Function(SSHSocket socket, SshAuthConfig auth);
typedef SshTransportLogger = void Function(String message);

class SshTransportException implements Exception {
  const SshTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SshTransportHandle {
  SshTransportHandle({
    required this.socket,
    required List<SshClientHandle> intermediateClients,
  }) : _intermediateClients = intermediateClients;

  final SSHSocket socket;
  final List<SshClientHandle> _intermediateClients;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final client in _intermediateClients.reversed) {
      client.close();
    }
    await socket.close();
  }
}

class DartSshClientHandle implements SshClientHandle {
  DartSshClientHandle(this.client);

  final SSHClient client;

  @override
  Future<void> get authenticated => client.authenticated;

  @override
  Future<SSHSocket> forwardLocal(String host, int port) {
    return client.forwardLocal(host, port);
  }

  @override
  void close() {
    client.close();
  }
}

SshClientHandle createDartSshClient(SSHSocket socket, SshAuthConfig auth) {
  final identities = auth.authType == 'privateKey'
      ? SSHKeyPair.fromPem(auth.privateKey, auth.privateKeyPassphrase)
      : null;
  final client = SSHClient(
    socket,
    username: auth.username,
    onPasswordRequest: auth.authType == 'password' ? () => auth.password : null,
    identities: identities,
  );
  return DartSshClientHandle(client);
}

class SshTransportFactory {
  SshTransportFactory({
    SshSocketConnector? connectSocket,
    Socks5Connector? socks5Connector,
    HttpProxyConnector? httpProxyConnector,
    SshClientCreator? createClient,
  }) : _connectSocket = connectSocket ?? SSHSocket.connect,
       _socks5Connector = socks5Connector ?? Socks5Connector(),
       _httpProxyConnector = httpProxyConnector ?? HttpProxyConnector(),
       _createClient = createClient ?? createDartSshClient;

  final SshSocketConnector _connectSocket;
  final Socks5Connector _socks5Connector;
  final HttpProxyConnector _httpProxyConnector;
  final SshClientCreator _createClient;

  Future<SshTransportHandle> open(
    SshConnectionConfig config, {
    SshTransportLogger? logger,
  }) async {
    if (config.proxyType.isEmpty) {
      final socket = await _connectSocket(config.host, config.port);
      return SshTransportHandle(socket: socket, intermediateClients: const []);
    }

    if (config.proxyType == 'proxyServer') {
      final proxy = config.proxy;
      if (proxy == null) {
        throw const SshTransportException('Proxy connection failed');
      }
      logger?.call(
        '使用代理服务器 ${proxy.name.isEmpty ? proxy.host : proxy.name} '
        '(${proxy.type.toUpperCase()}) - ${proxy.host}:${proxy.port}',
      );
      if (proxy.type == 'socks5') {
        final socket = await _socks5Connector.connect(
          proxyHost: proxy.host,
          proxyPort: proxy.port,
          targetHost: config.host,
          targetPort: config.port,
          username: proxy.username,
          password: proxy.password,
        );
        logger?.call('代理连接建立成功，准备通过代理连接目标服务器');
        return SshTransportHandle(
          socket: socket,
          intermediateClients: const [],
        );
      }
      if (proxy.type == 'http') {
        final socket = await _httpProxyConnector.connect(
          proxyHost: proxy.host,
          proxyPort: proxy.port,
          targetHost: config.host,
          targetPort: config.port,
          username: proxy.username,
          password: proxy.password,
        );
        logger?.call('代理连接建立成功，准备通过代理连接目标服务器');
        return SshTransportHandle(
          socket: socket,
          intermediateClients: const [],
        );
      }

      throw SshTransportException(
        'Unsupported native proxy type: ${proxy.type}',
      );
    }

    if (config.proxyType == 'jumpHosts') {
      if (config.jumpHosts.isEmpty) {
        throw const SshTransportException(
          'Jump host connection failed: empty chain',
        );
      }

      final clients = <SshClientHandle>[];
      logger?.call('准备通过跳板机连接目标服务器，共 ${config.jumpHosts.length} 跳');
      final firstJump = config.jumpHosts.first;
      logger?.call(
        '连接跳板机 1/${config.jumpHosts.length}: '
        '${firstJump.name.isEmpty ? firstJump.host : firstJump.name} - '
        '${firstJump.host}:${firstJump.port}',
      );
      SSHSocket socket = await _connectSocket(firstJump.host, firstJump.port);

      try {
        for (var i = 0; i < config.jumpHosts.length; i++) {
          final jumpHost = config.jumpHosts[i];
          final client = _createClient(socket, jumpHost);
          clients.add(client);
          try {
            await client.authenticated;
            logger?.call(
              '跳板机认证成功: '
              '${jumpHost.name.isEmpty ? jumpHost.host : jumpHost.name}',
            );
          } catch (_) {
            throw SshTransportException(
              'Jump host authentication failed: ${jumpHost.name.isEmpty ? jumpHost.host : jumpHost.name}',
            );
          }

          final nextHost = i == config.jumpHosts.length - 1
              ? config.host
              : config.jumpHosts[i + 1].host;
          final nextPort = i == config.jumpHosts.length - 1
              ? config.port
              : config.jumpHosts[i + 1].port;
          logger?.call(
            '跳板机转发: ${jumpHost.host}:${jumpHost.port} -> $nextHost:$nextPort',
          );
          try {
            socket = await client.forwardLocal(nextHost, nextPort);
          } catch (_) {
            throw SshTransportException(
              'Jump host forwarding failed: ${jumpHost.host} -> $nextHost',
            );
          }
        }

        logger?.call('跳板机连接成功，准备连接目标服务器');
        return SshTransportHandle(socket: socket, intermediateClients: clients);
      } catch (_) {
        for (final client in clients.reversed) {
          client.close();
        }
        await socket.close();
        rethrow;
      }
    }

    throw SshTransportException(
      'Unsupported native proxy type: ${config.proxyType}',
    );
  }
}
