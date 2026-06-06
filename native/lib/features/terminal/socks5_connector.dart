import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_transport.dart';

class SocketSshSocket implements SSHSocket {
  SocketSshSocket(this._socket, this._stream);

  final Socket _socket;
  final Stream<Uint8List> _stream;

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() {
    _socket.destroy();
  }
}

class Socks5Connector {
  Future<SSHSocket> connect({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String username = '',
    String password = '',
  }) async {
    final socket = await Socket.connect(proxyHost, proxyPort);
    final reader = _SocketReader(socket);
    try {
      final wantsAuth = username.isNotEmpty || password.isNotEmpty;
      socket.add(wantsAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]);
      final method = await reader.readExactly(2);
      if (method[0] != 0x05) {
        throw const SshTransportException('SOCKS5 proxy connection failed');
      }
      if (method[1] == 0xFF) {
        throw const SshTransportException('SOCKS5 authentication failed');
      }
      if (method[1] == 0x02) {
        await _authenticate(socket, reader, username, password);
      }

      socket.add(_connectRequest(targetHost, targetPort));
      final response = await reader.readExactly(5);
      if (response[1] != 0x00) {
        throw const SshTransportException('SOCKS5 target connection failed');
      }
      final addressRemainderLength = switch (response[3]) {
        0x01 => 3,
        0x03 => response[4] + 2,
        0x04 => 15,
        _ => throw const SshTransportException(
          'SOCKS5 target connection failed',
        ),
      };
      await reader.readExactly(addressRemainderLength);
      return SocketSshSocket(socket, reader.release());
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> _authenticate(
    Socket socket,
    _SocketReader reader,
    String username,
    String password,
  ) async {
    final user = utf8.encode(username);
    final pass = utf8.encode(password);
    socket.add([0x01, user.length, ...user, pass.length, ...pass]);
    final response = await reader.readExactly(2);
    if (response[1] != 0x00) {
      throw const SshTransportException('SOCKS5 authentication failed');
    }
  }

  List<int> _connectRequest(String host, int port) {
    final hostBytes = utf8.encode(host);
    return [
      0x05,
      0x01,
      0x00,
      0x03,
      hostBytes.length,
      ...hostBytes,
      (port >> 8) & 0xFF,
      port & 0xFF,
    ];
  }
}

class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        if (_released) {
          _streamController.add(Uint8List.fromList(data));
        } else {
          _buffer.addAll(data);
        }
      },
      onDone: () {
        _completer.complete();
        unawaited(_streamController.close());
      },
      onError: (Object error, StackTrace stackTrace) {
        _completer.completeError(error, stackTrace);
        _streamController.addError(error, stackTrace);
      },
    );
  }

  final _buffer = <int>[];
  final _completer = Completer<void>();
  final _streamController = StreamController<Uint8List>();
  late final StreamSubscription<List<int>> _subscription;
  bool _released = false;

  Future<List<int>> readExactly(int length) async {
    while (_buffer.length < length) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (_completer.isCompleted && _buffer.length < length) {
        await _subscription.cancel();
        throw const SshTransportException('SOCKS5 proxy connection failed');
      }
    }
    final bytes = _buffer.take(length).toList();
    _buffer.removeRange(0, length);
    return bytes;
  }

  Stream<Uint8List> release() {
    if (_released) return _streamController.stream;
    _released = true;
    if (_buffer.isNotEmpty) {
      _streamController.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
    return _streamController.stream;
  }
}
