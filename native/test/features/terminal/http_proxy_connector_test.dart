import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/http_proxy_connector.dart';

Future<String> readHttpHeaders(StreamIterator<List<int>> iterator) async {
  final bytes = <int>[];
  while (!_hasHeaderTerminator(bytes) && await iterator.moveNext()) {
    bytes.addAll(iterator.current);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

bool _hasHeaderTerminator(List<int> bytes) {
  for (var i = 0; i <= bytes.length - 4; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return true;
    }
  }
  return false;
}

void main() {
  test('performs http connect handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    late String request;

    unawaited(
      server.first.then((socket) async {
        final iterator = StreamIterator<List<int>>(socket);
        request = await readHttpHeaders(iterator);
        socket.add(utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      }),
    );

    final connector = HttpProxyConnector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
    );

    expect(request, contains('CONNECT example.com:22 HTTP/1.1'));
    expect(request, contains('Host: example.com:22'));
    await socket.close();
    await server.close();
  });

  test('sends basic auth header when credentials are present', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    late String request;

    unawaited(
      server.first.then((socket) async {
        final iterator = StreamIterator<List<int>>(socket);
        request = await readHttpHeaders(iterator);
        socket.add(utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      }),
    );

    final connector = HttpProxyConnector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
      username: 'u',
      password: 'p',
    );

    expect(request, contains('Proxy-Authorization: Basic dTpw'));
    await socket.close();
    await server.close();
  });
}
