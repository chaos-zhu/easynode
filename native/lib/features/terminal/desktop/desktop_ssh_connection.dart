import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../ssh_connection_config.dart';
import '../ssh_transport.dart';

/// Transport boundary used by the desktop workspace and by its offline tests.
abstract class DesktopTerminalConnection {
  Future<void> connect(
    SshConnectionConfig config, {
    required void Function(String) onData,
    required void Function(Object?) onClosed,
    required int columns,
    required int rows,
  });
  void write(String data);
  void resize(int columns, int rows);
  Future<Duration> ping();
  Future<void> close();
}

class DesktopSshConnection implements DesktopTerminalConnection {
  DesktopSshConnection({SshTransportFactory? transportFactory})
    : _factory = transportFactory ?? SshTransportFactory();

  final SshTransportFactory _factory;
  SshTransportHandle? _transport;
  SSHClient? _client;
  SSHSession? _shell;
  final _subscriptions = <StreamSubscription<String>>[];
  bool _closed = false;
  bool _reportedClosed = false;

  @override
  Future<void> connect(
    SshConnectionConfig config, {
    required void Function(String) onData,
    required void Function(Object?) onClosed,
    required int columns,
    required int rows,
  }) async {
    final transport = await _factory.open(config);
    if (_closed) {
      await transport.close();
      return;
    }
    _transport = transport;
    final handle =
        createDartSshClient(transport.socket, config) as DartSshClientHandle;
    _client = handle.client;
    await handle.authenticated;
    if (_closed) return;
    final shell = await handle.client.shell(
      pty: SSHPtyConfig(width: columns, height: rows),
    );
    if (_closed) {
      shell.close();
      return;
    }
    _shell = shell;
    void ended(Object? error) {
      if (_closed || _reportedClosed) return;
      _reportedClosed = true;
      onClosed(error);
    }

    // Stateful UTF-8 decoders keep Chinese/emoji intact across TCP chunks.
    for (final stream in [shell.stdout, shell.stderr]) {
      _subscriptions.add(
        stream
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen((data) {
              if (!_closed) onData(data);
            }, onError: ended),
      );
    }
    unawaited(
      shell.done.then(
        (_) => ended(null),
        onError: (Object error) => ended(error),
      ),
    );
    unawaited(
      handle.client.done.then(
        (_) => ended(null),
        onError: (Object error) => ended(error),
      ),
    );
  }

  @override
  void write(String data) =>
      _shell?.write(Uint8List.fromList(utf8.encode(data)));
  @override
  void resize(int columns, int rows) => _shell?.resizeTerminal(columns, rows);
  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await _client?.ping();
    return watch.elapsed;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _shell?.close();
    _client?.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _transport?.close();
    _shell = null;
    _client = null;
    _transport = null;
  }
}
