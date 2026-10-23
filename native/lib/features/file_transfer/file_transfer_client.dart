import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../core/api/cookie_store.dart';
import '../../core/security/server_certificate_trust.dart';
import '../../state/auth_notifier.dart';
import '../../state/storage_providers.dart';
import '../auth/auth_session.dart';
import '../ai_agent/agent_models.dart';

final fileTransferClientProvider = Provider.autoDispose<FileTransferClient>((
  ref,
) {
  final client = FileTransferClient(
    session: ref.watch(authProvider).session!,
    cookies: ref.watch(cookieStoreProvider),
    trust: ref.watch(certificateTrustProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Browsing remains direct SFTP. Only the server creates and executes transfers,
/// including its existing Plus check and task persistence.
class FileTransferClient extends ChangeNotifier {
  FileTransferClient({
    required this.session,
    required this.cookies,
    required this.trust,
    this.socketFactory = sio.io,
  });
  final AuthSession session;
  final SessionCookieStore cookies;
  final ServerCertificateTrustStore trust;
  final sio.Socket Function(String, Map<String, dynamic>) socketFactory;
  sio.Socket? _socket;
  bool connecting = false,
      connected = false,
      submitting = false,
      _disposed = false;
  String? error;
  List<Map<String, dynamic>> tasks = [];
  int completedRevision = 0;
  final pending = <String>{};
  int get runningCount => tasks.where((t) => t['status'] == 'running').length;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect() async {
    if (connecting || connected || _disposed) return;
    connecting = true;
    error = null;
    _changed();
    try {
      final cookie = await cookies.readCookieHeader();
      if (_disposed) return;
      if (cookie == null || cookie.isEmpty) {
        throw StateError('Missing session cookie');
      }
      final previous = _socket;
      _socket = null;
      previous?.dispose();
      _connect(_addresses(), 0, cookie);
    } catch (e) {
      connecting = false;
      error = '$e';
      _changed();
    }
  }

  List<String> _addresses() {
    final uri = Uri.tryParse(session.serverAddress);
    final port = uri?.scheme == 'https' ? 8092 : 8082;
    return [
      if (kDebugMode && uri != null && uri.host.isNotEmpty && uri.port != port)
        uri.replace(port: port).toString(),
      session.serverAddress,
    ];
  }

  void _connect(List<String> addresses, int index, String cookie) {
    final options =
        sio.OptionBuilder()
            .setTransports(['websocket'])
            .setPath('/file-transfer/')
            .setAuth({'token': session.token})
            .setExtraHeaders({
              'Cookie': cookie,
              'Origin': session.serverAddress,
            })
            .setWebSocketConnector(trust.connectWebSocket)
            .disableAutoConnect()
            .disableReconnection()
            .build()
          ..addAll({'forceNew': true, 'multiplex': false});
    final socket = _socket = socketFactory(addresses[index], options);
    socket.onConnect((_) {
      connecting = false;
      connected = true;
      error = null;
      socket.emit('get_tasks');
      _changed();
    });
    socket.on('tasks_list', (data) {
      tasks = mapList(data).map((t) => Map<String, dynamic>.from(t)).toList();
      _sort();
      _changed();
    });
    socket.on('task_progress', (data) {
      if (data is! Map) return;
      final task = tasks
          .where((t) => t['taskId'] == data['taskId'])
          .firstOrNull;
      if (task == null) return;
      task.addAll(stringMap(data));
      task['progress'] =
          data['overallProgress'] ?? data['progress'] ?? task['progress'];
      _changed();
    });
    socket.on('task_status_changed', (data) {
      if (data is! Map) return;
      final task = tasks
          .where((t) => t['taskId'] == data['taskId'])
          .firstOrNull;
      task?.addAll(stringMap(data));
      if (data['status'] != 'running') {
        completedRevision++;
        pending.remove('${data['taskId']}');
        refresh();
      }
      _sort();
      _changed();
    });
    for (final event in [
      'task_started',
      'task_cancelled',
      'task_deleted',
      'tasks_cleared',
    ]) {
      socket.on(event, (data) {
        if (event == 'task_started') submitting = false;
        if (event == 'task_cancelled') completedRevision++;
        if (data is Map) pending.remove('${data['taskId']}');
        refresh();
        _changed();
      });
    }
    socket.on('task_failed', (data) {
      submitting = false;
      error = data is Map ? '${data['message'] ?? 'Transfer failed'}' : '$data';
      refresh();
      _changed();
    });
    socket.on('error', (data) {
      submitting = false;
      pending.clear();
      error = data is Map
          ? '${data['message'] ?? data['error'] ?? 'Transfer failed'}'
          : '$data';
      _changed();
    });
    socket.onConnectError((e) {
      if (!identical(_socket, socket)) return;
      _socket = null;
      socket.dispose();
      if (index + 1 < addresses.length) {
        _connect(addresses, index + 1, cookie);
      } else {
        connecting = false;
        error = '$e';
        _changed();
      }
    });
    socket.onDisconnect((_) {
      if (!identical(_socket, socket)) return;
      connected = connecting = submitting = false;
      pending.clear();
      error = 'Connection lost';
      _changed();
    });
    socket.connect();
  }

  void _sort() => tasks.sort((a, b) {
    final running = (a['status'] == 'running' ? 0 : 1).compareTo(
      b['status'] == 'running' ? 0 : 1,
    );
    return running != 0
        ? running
        : intValue(b['updateTime']).compareTo(intValue(a['updateTime']));
  });
  void refresh() {
    if (connected) _socket?.emit('get_tasks');
  }

  void start(Map<String, dynamic> config) {
    if (!connected || submitting) return;
    submitting = true;
    error = null;
    _socket!.emit('start_transfer', config);
    _changed();
  }

  void action(String event, [String? taskId]) {
    if (!connected) return;
    if (taskId != null && !pending.add(taskId)) return;
    error = null;
    _socket!.emit(event, taskId == null ? null : {'taskId': taskId});
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket?.dispose();
    super.dispose();
  }
}
