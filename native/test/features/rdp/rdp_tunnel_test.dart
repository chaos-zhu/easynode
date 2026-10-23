import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easynode_native/features/rdp/rdp_tunnel.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loopback bridge relays both directions and releases transport on close',
    () async {
      final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final request = Completer<String>();
      target.listen((socket) {
        accepted.complete(socket);
        socket.listen((data) {
          request.complete(utf8.decode(data));
          socket.add(utf8.encode('rdp-response'));
        });
      });
      addTearDown(target.close);
      final tunnel = await RdpTunnel.open(
        SshConnectionConfig.fromJson({
          'host': InternetAddress.loopbackIPv4.address,
          'port': target.port,
        }),
      );
      addTearDown(tunnel.close);
      final local = await Socket.connect(
        InternetAddress.loopbackIPv4,
        tunnel.port,
      );
      addTearDown(local.destroy);
      final response = Completer<String>();
      final closed = Completer<void>();
      local.listen(
        (data) => response.complete(utf8.decode(data)),
        onDone: closed.complete,
      );
      local.add(utf8.encode('rdp-request'));
      expect(
        await request.future.timeout(const Duration(seconds: 5)),
        'rdp-request',
      );
      expect(
        await response.future.timeout(const Duration(seconds: 5)),
        'rdp-response',
      );
      final remote = await accepted.future;
      addTearDown(remote.destroy);
      await tunnel.close();
      await closed.future.timeout(const Duration(seconds: 5));
    },
  );
}
