import 'dart:async';
import 'dart:io';

import '../terminal/ssh_connection_config.dart';
import '../terminal/ssh_transport.dart';

/// A loopback-only bridge lets the local RDP engine reuse native HTTP/SOCKS and
/// SSH jump transports. Each accepted stream owns its forwarding chain.
class RdpTunnel {
  RdpTunnel._(this._listener, this._config, this._factory) {
    _listener.listen(_accept);
  }
  final ServerSocket _listener;
  final SshConnectionConfig _config;
  final SshTransportFactory _factory;
  final _sockets = <Socket>{};
  final _relays = <Future<void>>{};
  bool _closed = false;
  int get port => _listener.port;

  static Future<RdpTunnel> open(
    SshConnectionConfig config, {
    SshTransportFactory? factory,
  }) async => RdpTunnel._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    config,
    factory ?? SshTransportFactory(),
  );

  Future<void> _accept(Socket local) async {
    _sockets.add(local);
    SshTransportHandle? remote;
    Future<void>? upload;
    final stopped = Completer<void>();
    try {
      remote = await _factory.open(_config);
      if (_closed) return;
      _relays.add(stopped.future);
      upload = remote.socket.sink.addStream(local);
      // Closing either direction closes the other half and its jump chain.
      await Future.any([local.addStream(remote.socket.stream), upload]);
    } catch (_) {
      // The engine reports the connection error; do not expose credentials in logs.
    } finally {
      local.destroy();
      _sockets.remove(local);
      // Stop the input stream before closing its bound sink. Closing a sink
      // while addStream is active throws instead of releasing the transport.
      try {
        await upload;
      } catch (_) {}
      try {
        await remote?.close();
      } catch (_) {}
      stopped.complete();
      _relays.remove(stopped.future);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _listener.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await Future.wait(_relays.toList());
  }
}
