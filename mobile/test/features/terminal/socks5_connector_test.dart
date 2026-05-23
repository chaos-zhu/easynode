import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/socks5_connector.dart';

Future<List<int>> readExactlyFromIterator(
  StreamIterator<List<int>> iterator,
  int length,
) async {
  final bytes = <int>[];
  while (bytes.length < length && await iterator.moveNext()) {
    bytes.addAll(iterator.current);
  }
  return bytes.take(length).toList();
}

void main() {
  test('performs no-auth socks5 handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final captured = <List<int>>[];

    unawaited(
      server.first.then((socket) async {
        final iterator = StreamIterator<List<int>>(socket);
        captured.add(await readExactlyFromIterator(iterator, 3));
        socket.add([0x05, 0x00]);
        captured.add(await readExactlyFromIterator(iterator, 18));
        socket.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]);
      }),
    );

    final connector = Socks5Connector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
    );

    expect(captured.first, [0x05, 0x01, 0x00]);
    expect(captured.last.take(5), [0x05, 0x01, 0x00, 0x03, 11]);
    await socket.close();
    await server.close();
  });

  test('performs username password socks5 handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final captured = <List<int>>[];

    unawaited(
      server.first.then((socket) async {
        final iterator = StreamIterator<List<int>>(socket);
        captured.add(await readExactlyFromIterator(iterator, 4));
        socket.add([0x05, 0x02]);
        captured.add(await readExactlyFromIterator(iterator, 5));
        socket.add([0x01, 0x00]);
        captured.add(await readExactlyFromIterator(iterator, 18));
        socket.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]);
      }),
    );

    final connector = Socks5Connector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
      username: 'u',
      password: 'p',
    );

    expect(captured.first, [0x05, 0x02, 0x00, 0x02]);
    expect(captured[1], [0x01, 0x01, 117, 0x01, 112]);
    await socket.close();
    await server.close();
  });
}
