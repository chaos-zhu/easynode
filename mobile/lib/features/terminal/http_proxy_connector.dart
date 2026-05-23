import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'socks5_connector.dart';
import 'ssh_transport.dart';

class HttpProxyConnector {
  Future<SSHSocket> connect({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String username = '',
    String password = '',
  }) async {
    final socket = await Socket.connect(proxyHost, proxyPort);
    final reader = _HttpProxyReader(socket);
    try {
      socket.add(
        utf8.encode(
          _connectRequest(
            targetHost: targetHost,
            targetPort: targetPort,
            username: username,
            password: password,
          ),
        ),
      );
      final response = await reader.readHeaders();
      final statusLine = response.isEmpty ? '' : response.first;
      if (!statusLine.contains(' 200 ')) {
        throw const SshTransportException(
          'HTTP proxy target connection failed',
        );
      }
      return SocketSshSocket(socket, reader.release());
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  String _connectRequest({
    required String targetHost,
    required int targetPort,
    required String username,
    required String password,
  }) {
    final target = '$targetHost:$targetPort';
    final headers = <String>[
      'CONNECT $target HTTP/1.1',
      'Host: $target',
      'Proxy-Connection: Keep-Alive',
    ];
    if (username.isNotEmpty || password.isNotEmpty) {
      final token = base64Encode(utf8.encode('$username:$password'));
      headers.add('Proxy-Authorization: Basic $token');
    }
    return '${headers.join('\r\n')}\r\n\r\n';
  }
}

class _HttpProxyReader {
  _HttpProxyReader(Socket socket) {
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

  Future<List<String>> readHeaders() async {
    while (!_hasHeaderTerminator()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (_completer.isCompleted && !_hasHeaderTerminator()) {
        await _subscription.cancel();
        throw const SshTransportException('HTTP proxy connection failed');
      }
    }
    final end = _headerEndIndex();
    final headerBytes = _buffer.take(end).toList();
    _buffer.removeRange(0, end + 4);
    return utf8.decode(headerBytes, allowMalformed: true).split('\r\n');
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

  bool _hasHeaderTerminator() => _headerEndIndex() >= 0;

  int _headerEndIndex() {
    for (var i = 0; i <= _buffer.length - 4; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}
