import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/batch/batch_execution.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:socket_io_client/src/manager.dart';

class _Socket extends sio.Socket {
  _Socket({this.connectError})
    : super(
        Manager(
          uri: 'https://panel.example.com',
          options: {'autoConnect': false},
        ),
        '/',
        {},
      );
  final sent = <(String, dynamic)>[];
  final String? connectError;
  bool disposed = false;
  @override
  sio.Socket connect() {
    if (connectError != null) {
      emitReserved('connect_error', connectError);
      return this;
    }
    connected = true;
    emitReserved('connect');
    return this;
  }

  @override
  void emit(String event, [dynamic data]) {
    sent.add((event, data));
  }

  @override
  void dispose() {
    disposed = true;
    if (connected) emitReserved('disconnect', 'io client disconnect');
    connected = false;
    clearListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('development sockets bypass the REST-only Web dev port', () {
    expect(batchServerCandidates('http://localhost:18090'), [
      'http://localhost:8082',
      'http://localhost:18090',
    ]);
    expect(batchServerCandidates('https://localhost:18090'), [
      'https://localhost:8092',
      'https://localhost:18090',
    ]);
    expect(batchServerCandidates('http://localhost:8082'), [
      'http://localhost:8082',
    ]);
    expect(batchServerCandidates('https://panel.example.com', debug: false), [
      'https://panel.example.com',
    ]);
  });

  test(
    'unavailable debug port falls back and submits the command once',
    () async {
      final cookie = SessionCookieStore.memory();
      await cookie.saveFromSetCookieHeaders(['session=abc']);
      final addresses = <String>[];
      final sockets = <_Socket>[];
      final execution = BatchExecution(
        session: const AuthSession(
          serverAddress: 'https://panel.example.com',
          username: 'admin',
          token: 'jwt',
          deviceId: 'device',
        ),
        cookies: cookie,
        trust: ServerCertificateTrustStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        socketFactory: (address, _) {
          addresses.add(address);
          final socket = _Socket(
            connectError: sockets.isEmpty ? 'unavailable' : null,
          );
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(execution.dispose);
      await execution.start(['h1'], 'uptime', 120);
      expect(addresses, [
        'https://panel.example.com:8092',
        'https://panel.example.com',
      ]);
      expect(sockets.first.disposed, true);
      expect(sockets.first.sent, isEmpty);
      expect(sockets.last.sent.single.$1, 'ws_onekey');
      expect(execution.active, true);
      expect(execution.error, isNull);
      sockets.last.emitReserved('output', [
        {
          'batchId': 'batch',
          'hostId': 'h1',
          'name': 'Production',
          'status': '执行中',
          'result': 'up 10 days',
        },
      ]);
      expect(execution.records.single.name, 'Production');
    },
  );
  test(
    'authenticated server socket executes and stops hosts without local SSH',
    () async {
      final cookie = SessionCookieStore.memory();
      await cookie.saveFromSetCookieHeaders(['session=abc; HttpOnly']);
      final socket = _Socket();
      late Map<String, dynamic> options;
      final execution = BatchExecution(
        session: const AuthSession(
          serverAddress: 'https://panel.example.com',
          username: 'admin',
          token: 'jwt',
          deviceId: 'device',
        ),
        cookies: cookie,
        trust: ServerCertificateTrustStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        socketFactory: (url, opts) {
          expect(url, 'https://panel.example.com:8092');
          options = opts;
          return socket;
        },
      );
      addTearDown(execution.dispose);
      await execution.start(['h1', 'h2'], 'uptime', 60);
      expect(options['path'], '/onekey/');
      expect(options['auth'], {'token': 'jwt'});
      expect(options['extraHeaders']['Cookie'], 'session=abc');
      expect(options['reconnection'], false);
      expect(socket.sent.single.$1, 'ws_onekey');
      expect(socket.sent.single.$2, {
        'hostIds': ['h1', 'h2'],
        'token': 'jwt',
        'command': 'uptime',
        'timeout': 60,
      });
      await execution.start(['h3'], 'ignored', 60);
      expect(socket.sent.length, 1);
      socket.emitReserved('output', [
        {
          'hostId': 'h1',
          'batchId': 'batch',
          'status': '执行中',
          'result': 'live\n',
        },
      ]);
      expect(execution.records.single.output, 'live\n');
      expect(execution.records.single.canStop, true);
      execution.stop(hostId: 'h1');
      expect(socket.sent.last.$1, 'ws_onekey_stop');
      expect(socket.sent.last.$2, {'scope': 'host', 'hostId': 'h1'});
      socket.emitReserved('stop_result', {
        'scope': 'host',
        'hostId': 'h1',
        'ok': false,
        'message': 'cannot stop',
      });
      expect(execution.stoppingHosts, isEmpty);
      expect(execution.error, 'cannot stop');
      execution.stop();
      expect(socket.sent.last.$1, 'ws_onekey_stop');
      expect(socket.sent.last.$2, {'scope': 'all'});
      socket.emitReserved('stop_result', {
        'scope': 'all',
        'ok': true,
        'persisted': true,
      });
      expect(execution.active, false);
      expect(execution.completed, 1);
      socket.emitReserved('exec_complete');
      expect(execution.completed, 1);
    },
  );
  test(
    'creation and network failures release execution state for retry',
    () async {
      final cookie = SessionCookieStore.memory();
      await cookie.saveFromSetCookieHeaders(['session=abc']);
      final sockets = <_Socket>[];
      final execution = BatchExecution(
        session: const AuthSession(
          serverAddress: 'https://panel.example.com',
          username: 'admin',
          token: 'jwt',
          deviceId: 'device',
        ),
        cookies: cookie,
        trust: ServerCertificateTrustStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        socketFactory: (_, _) {
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(execution.dispose);
      await execution.start(['h1'], 'ls', 60);
      sockets.last.emitReserved('create_fail', 'No hosts');
      expect(execution.active, false);
      expect(execution.error, 'No hosts');
      await execution.start(['h1'], 'ls', 60);
      expect(sockets.first.disposed, true);
      expect(execution.active, true);
      expect(execution.completed, 1);
      sockets.last.emitReserved('disconnect');
      expect(execution.active, false);
      expect(execution.error, 'Connection lost');
    },
  );
}
