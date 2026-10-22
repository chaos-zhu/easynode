import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../core/api/cookie_store.dart';
import '../../core/security/server_certificate_trust.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/storage_providers.dart';
import '../auth/auth_session.dart';
import 'batch_repository.dart';

final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepository(ref.watch(apiClientProvider)),
);
final batchExecutionProvider = Provider.autoDispose<BatchExecution>((ref) {
  final execution = BatchExecution(
    session: ref.watch(authProvider).session!,
    cookies: ref.watch(cookieStoreProvider),
    trust: ref.watch(certificateTrustProvider),
  );
  ref.onDispose(execution.dispose);
  return execution;
});

/// Only the server executes commands. This client owns transport and progress.
class BatchExecution extends ChangeNotifier {
  BatchExecution({
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
  Timer? _timer;
  List<BatchRecord> records = [];
  final stoppingHosts = <String>{};
  bool active = false, stopping = false, _disposed = false;
  int remaining = 0, completed = 0;
  String? error;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(List<String> hosts, String command, int timeout) async {
    if (active) return;
    active = true;
    error = null;
    records = [];
    remaining = timeout;
    stoppingHosts.clear();
    _changed();
    try {
      final cookie = await cookies.readCookieHeader();
      if (_disposed) return;
      if (cookie == null || cookie.isEmpty) {
        throw StateError('Missing session cookie');
      }
      final previousSocket = _socket;
      _socket = null;
      previousSocket?.dispose();
      _connect(
        batchServerCandidates(session.serverAddress),
        0,
        cookie,
        hosts,
        command,
        timeout,
      );
    } catch (e) {
      _finish('$e');
    }
  }

  void _connect(
    List<String> candidates,
    int index,
    String cookie,
    List<String> hosts,
    String command,
    int timeout,
  ) {
    final options = sio.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/onekey/')
        .setAuth({'token': session.token})
        .setExtraHeaders({'Cookie': cookie, 'Origin': session.serverAddress})
        .setWebSocketConnector(trust.connectWebSocket)
        .disableAutoConnect()
        .disableReconnection()
        .build();
    options.addAll({'forceNew': true, 'multiplex': false});
    final socket = _socket = socketFactory(candidates[index], options);
    socket.onConnect((_) {
      socket.emit('ws_onekey', {
        'hostIds': hosts,
        'token': session.token,
        'command': command,
        'timeout': timeout,
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        remaining = (remaining - 1).clamp(0, timeout);
        _changed();
      });
    });
    socket.on('ready', (_) {
      records = [];
      _changed();
    });
    socket.on('output', (data) {
      if (data is List) {
        records = data
            .whereType<Map>()
            .map((v) => BatchRecord.fromJson(v, pending: true))
            .toList();
        _changed();
      }
    });
    socket.on('stop_result', (data) {
      if (data is! Map) return;
      if (data['scope'] == 'host') {
        stoppingHosts.remove('${data['hostId']}');
        if (data['ok'] != true) error = '${data['message'] ?? 'Stop failed'}';
        _changed();
      } else if (data['ok'] == true) {
        _finish(data['persisted'] == false ? '${data['message']}' : null);
      } else {
        stopping = false;
        error = '${data['message'] ?? 'Stop failed'}';
        _changed();
      }
    });
    socket.on('exec_complete', (_) => _finish());
    socket.on(
      'exec_timeout',
      (data) => _finish(
        data is Map
            ? '${data['reason'] ?? 'Execution timeout'}'
            : 'Execution timeout',
      ),
    );
    socket.on('create_fail', (data) => _finish('$data'));
    socket.onConnectError((e) {
      if (!identical(_socket, socket)) return;
      _socket = null;
      socket.dispose();
      if (index + 1 < candidates.length) {
        _connect(candidates, index + 1, cookie, hosts, command, timeout);
      } else {
        _finish('$e');
      }
    });
    socket.onError((e) {
      if (identical(_socket, socket)) _finish('$e');
    });
    socket.onDisconnect((_) {
      if (identical(_socket, socket) && active) _finish('Connection lost');
    });
    socket.connect();
  }

  void stop({String? hostId}) {
    if (!active || _socket?.connected != true) return;
    if (hostId == null) {
      stopping = true;
    } else {
      stoppingHosts.add(hostId);
    }
    _socket!.emit('ws_onekey_stop', {
      'scope': hostId == null ? 'all' : 'host',
      'hostId': ?hostId,
    });
    _changed();
  }

  void _finish([String? message]) {
    if (_disposed || !active) return;
    active = false;
    stopping = false;
    stoppingHosts.clear();
    remaining = 0;
    _timer?.cancel();
    error = message;
    completed++;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}

/// Debug Web serves REST through Vite, while sockets use the server port.
/// Match the existing Docker/AI clients and fall back to the entered address.
List<String> batchServerCandidates(String address, {bool debug = kDebugMode}) {
  if (!debug) return [address];
  final uri = Uri.tryParse(address);
  if (uri == null || uri.host.isEmpty) return [address];
  final serverPort = uri.scheme == 'http'
      ? 8082
      : uri.scheme == 'https'
      ? 8092
      : null;
  return [
    if (serverPort != null && uri.port != serverPort)
      uri.replace(port: serverPort).toString(),
    address,
  ];
}
