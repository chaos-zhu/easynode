import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/file_transfer/file_transfer_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:socket_io_client/src/manager.dart';

class _Socket extends sio.Socket {
  _Socket({this.fail = false})
    : super(
        Manager(
          uri: 'https://panel.example.com',
          options: {'autoConnect': false},
        ),
        '/',
        {},
      );
  final bool fail;
  final sent = <(String, dynamic)>[];
  bool disposed = false;
  @override
  sio.Socket connect() {
    if (fail) {
      emitReserved('connect_error', 'unavailable');
    } else {
      connected = true;
      emitReserved('connect');
    }
    return this;
  }

  @override
  void emit(String event, [dynamic data]) {
    sent.add((event, data));
  }

  @override
  void dispose() {
    disposed = true;
    connected = false;
    clearListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<FileTransferClient> client(
    sio.Socket Function(String, Map<String, dynamic>) factory,
  ) async {
    final cookies = SessionCookieStore.memory();
    await cookies.saveFromSetCookieHeaders(['session=abc; HttpOnly']);
    return FileTransferClient(
      session: const AuthSession(
        serverAddress: 'https://panel.example.com:18090',
        username: 'admin',
        token: 'jwt',
        deviceId: 'device',
      ),
      cookies: cookies,
      trust: ServerCertificateTrustStore(
        SecureAppStorage(const FlutterSecureStorage()),
      ),
      socketFactory: factory,
    );
  }

  test(
    'uses server transfer feature with token/cookie, debug port fallback and single submission',
    () async {
      final addresses = <String>[];
      final sockets = <_Socket>[];
      final c = await client((url, options) {
        addresses.add(url);
        expect(options['path'], '/file-transfer/');
        expect(options['auth'], {'token': 'jwt'});
        expect(options['extraHeaders']['Cookie'], 'session=abc');
        final socket = _Socket(fail: sockets.isEmpty);
        sockets.add(socket);
        return socket;
      });
      addTearDown(c.dispose);
      await c.connect();
      expect(addresses, [
        'https://panel.example.com:8092',
        'https://panel.example.com:18090',
      ]);
      expect(sockets.first.disposed, isTrue);
      expect(c.connected, isTrue);
      final config = {
        'sourceHostId': 'a',
        'targetHostId': 'b',
        'sourcePaths': [
          {'path': '/tmp/file', 'type': '-', 'size': 10},
        ],
        'targetPath': '/srv',
        'method': 'rsync',
        'options': {'partial': true},
      };
      c.start(config);
      c.start(config);
      expect(
        sockets.last.sent.where((e) => e.$1 == 'start_transfer').toList(),
        [('start_transfer', config)],
      );
      sockets.last.emitReserved('task_failed', {'message': 'Plus required'});
      expect(c.submitting, isFalse);
      expect(c.error, 'Plus required');
      c.start(config);
      sockets.last.emitReserved('task_started', {'taskId': 't'});
      expect(c.submitting, isFalse);
    },
  );
  test(
    'sorts running tasks, merges progress, refreshes on completion, and clears pending actions',
    () async {
      final socket = _Socket();
      final c = await client((_, _) => socket);
      addTearDown(c.dispose);
      await c.connect();
      socket.emitReserved('tasks_list', [
        {'taskId': 'old', 'status': 'completed', 'updateTime': 1},
        {'taskId': 'new', 'status': 'completed', 'updateTime': 3},
        {'taskId': 'running', 'status': 'running', 'updateTime': 2},
      ]);
      expect(c.tasks.map((t) => t['taskId']), ['running', 'new', 'old']);
      socket.emitReserved('task_progress', {
        'taskId': 'running',
        'overallProgress': 42.5,
        'completedFiles': 3,
        'totalFiles': 8,
        'currentFile': '/srv/a',
        'isVerifying': false,
      });
      expect(c.tasks.first['progress'], 42.5);
      expect(c.tasks.first['completedFiles'], 3);
      c.action('cancel_task', 'running');
      c.action('cancel_task', 'running');
      expect(socket.sent.where((e) => e.$1 == 'cancel_task').length, 1);
      socket.emitReserved('task_cancelled', {'taskId': 'running'});
      expect(c.pending, isEmpty);
      final revision = c.completedRevision;
      socket.emitReserved('task_status_changed', {
        'taskId': 'running',
        'status': 'completed',
      });
      expect(c.completedRevision, revision + 1);
      expect(c.tasks.first['taskId'], 'new');
      c.action('delete_task', 'old');
      socket.emitReserved('error', {'message': 'Delete failed'});
      expect(c.pending, isEmpty);
      socket.emitReserved('disconnect', 'network lost');
      expect(c.connected, isFalse);
      final count = socket.sent.length;
      c.start({});
      expect(socket.sent.length, count);
    },
  );
  test(
    'disposing the browser disconnects the socket without cancelling server tasks',
    () async {
      final socket = _Socket();
      final c = await client((_, _) => socket);
      await c.connect();
      c.dispose();
      expect(socket.disposed, isTrue);
      expect(socket.sent.any((e) => e.$1 == 'cancel_task'), isFalse);
    },
  );
}
