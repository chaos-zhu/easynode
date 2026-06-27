import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../core/api/cookie_store.dart';
import '../auth/auth_session.dart';
import 'docker_container.dart';

class DockerSocketClient {
  DockerSocketClient({
    required AuthSession authSession,
    required SessionCookieStore cookieStore,
    required this.hostId,
  }) : _authSession = authSession,
       _cookieStore = cookieStore;

  final AuthSession _authSession;
  final SessionCookieStore _cookieStore;
  final String hostId;

  final StreamController<List<DockerContainer>> _containersController =
      StreamController<List<DockerContainer>>.broadcast();
  final StreamController<String> _logsController =
      StreamController<String>.broadcast();
  final StreamController<DockerOperationResult> _operationController =
      StreamController<DockerOperationResult>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  sio.Socket? _socket;
  List<String> _serverCandidates = const [];
  int _candidateIndex = 0;
  bool _disposed = false;

  Stream<List<DockerContainer>> get containersStream =>
      _containersController.stream;
  Stream<String> get logsStream => _logsController.stream;
  Stream<DockerOperationResult> get operationStream =>
      _operationController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get connectedStream => _connectedController.stream;

  bool get connected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_disposed) return;
    disconnect(closeStreams: false);
    final cookie = await _cookieStore.readCookieHeader();
    _serverCandidates = _buildServerCandidates(_authSession.serverAddress);
    _candidateIndex = 0;
    if (cookie == null || cookie.isEmpty) {
      _emitError('No Cookie');
      return;
    }

    _connectCandidate(cookie);
  }

  void _connectCandidate(String cookie) {
    if (_disposed || _candidateIndex >= _serverCandidates.length) return;
    final serverAddress = _serverCandidates[_candidateIndex];

    final options = sio.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/docker/')
        .setAuth({'token': _authSession.token})
        .setExtraHeaders({
          'Cookie': cookie,
          'Origin': _authSession.serverAddress,
        })
        .disableAutoConnect()
        .disableReconnection()
        .build();
    options['forceNew'] = true;
    options['multiplex'] = false;
    options['query'] = {'hostId': hostId};

    final socket = sio.io(serverAddress, options);

    socket.onConnect((_) {
      _connectedController.add(true);
      socket.emit('ws_docker', {'hostId': hostId});
    });

    socket.onConnectError((error) {
      final message = _stringifyError(error);
      socket.dispose();
      if (_tryNextCandidate(cookie)) return;
      _emitError(message);
    });

    socket.onError((error) {
      _emitError(_stringifyError(error));
    });

    socket.onDisconnect((_) {
      if (!_disposed) _connectedController.add(false);
    });

    socket.on('docker_containers_data', (data) {
      if (data is! List) return;
      _containersController.add(
        data
            .whereType<Map>()
            .map(
              (item) => DockerContainer.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(growable: false),
      );
    });

    socket.on('docker_containers_logs', (data) {
      _logsController.add(data?.toString() ?? '');
    });

    socket.on('docker_operation_result', (data) {
      _operationController.add(DockerOperationResult.fromJson(data));
    });

    socket.on('docker_connect_fail', (_) {
      _emitError('docker_connect_fail');
    });

    socket.on('docker_not_plus', (_) {
      _emitError('docker_not_plus');
    });

    _socket = socket;
    socket.connect();
  }

  bool _tryNextCandidate(String cookie) {
    final hasNext = _candidateIndex + 1 < _serverCandidates.length;
    if (!hasNext) return false;
    _candidateIndex++;
    _connectCandidate(cookie);
    return true;
  }

  void refresh() {
    _socket?.emit('docker_get_containers_data');
  }

  void getLogs(String containerId, {int tail = 2000}) {
    _socket?.emit('docker_get_containers_logs', {
      'containerId': containerId,
      'tail': tail,
    });
  }

  void start(String containerId) =>
      _socket?.emit('docker_start_container', {'containerId': containerId});

  void stop(String containerId) =>
      _socket?.emit('docker_stop_container', {'containerId': containerId});

  void restart(String containerId) =>
      _socket?.emit('docker_restart_container', {'containerId': containerId});

  void delete(String containerId) =>
      _socket?.emit('docker_delete_container', {'containerId': containerId});

  void _emitError(String message) {
    if (!_disposed) _errorController.add(message);
  }

  String _stringifyError(Object? error) {
    if (error == null) return 'Connection error';
    if (error is Map) {
      final message = error['message'] ?? error['error'] ?? error['data'];
      return message?.toString() ?? error.toString();
    }
    return error.toString();
  }

  List<String> _buildServerCandidates(String serverAddress) {
    if (!kDebugMode) return [serverAddress];
    final parsed = Uri.tryParse(serverAddress);
    if (parsed == null || parsed.host.isEmpty) return [serverAddress];
    final candidates = <String>[];
    if (parsed.scheme == 'http' && parsed.port != 8082) {
      candidates.add(parsed.replace(port: 8082).toString());
    }
    if (parsed.scheme == 'https' && parsed.port != 8092) {
      candidates.add(parsed.replace(port: 8092).toString());
    }
    candidates.add(serverAddress);
    return LinkedHashSet<String>.from(candidates).toList(growable: false);
  }

  void disconnect({bool closeStreams = true}) {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    if (closeStreams) {
      _disposed = true;
      _containersController.close();
      _logsController.close();
      _operationController.close();
      _errorController.close();
      _connectedController.close();
    }
  }
}
