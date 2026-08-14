import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../core/api/cookie_store.dart';
import '../auth/auth_session.dart';
import 'agent_models.dart';

enum AgentConnectionStatus { disconnected, connecting, connected }

Duration agentReconnectDelay(int attempt) {
  const delays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];
  return delays[attempt.clamp(0, delays.length - 1)];
}

Map<String, dynamic> buildOpsAgentRunPayload({
  required String input,
  required String modelId,
  required String permission,
  required List<String> hostIds,
  String? sessionId,
}) => {
  if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
  'input': input.trim(),
  'modelId': modelId,
  'permission': permission,
  'hostIds': List<String>.unmodifiable(hostIds),
  'scope': 'ops',
};

class AgentSocketClient {
  AgentSocketClient({
    required AuthSession authSession,
    required SessionCookieStore cookieStore,
  }) : _authSession = authSession,
       _cookieStore = cookieStore;

  final AuthSession _authSession;
  final SessionCookieStore _cookieStore;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _connections = StreamController<AgentConnectionStatus>.broadcast();
  final _errors = StreamController<String>.broadcast();

  sio.Socket? _socket;
  List<String> _serverCandidates = const [];
  int _candidateIndex = 0;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _allowReconnect = false;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<AgentConnectionStatus> get connections => _connections.stream;
  Stream<String> get errors => _errors.stream;
  bool get connected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_disposed || connected) return;
    _allowReconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final staleSocket = _socket;
    _socket = null;
    staleSocket?.dispose();
    final cookie = await _cookieStore.readCookieHeader();
    if (cookie == null || cookie.isEmpty) {
      _allowReconnect = false;
      _connections.add(AgentConnectionStatus.disconnected);
      _errors.add('No Cookie');
      return;
    }
    _serverCandidates = _buildServerCandidates(_authSession.serverAddress);
    _candidateIndex = 0;
    _connections.add(AgentConnectionStatus.connecting);
    _connectCandidate(cookie);
  }

  void _connectCandidate(String cookie) {
    if (_disposed || _candidateIndex >= _serverCandidates.length) return;
    final serverAddress = _serverCandidates[_candidateIndex];
    final options = sio.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/ai-agent/')
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

    final socket = sio.io(serverAddress, options);
    var didConnect = false;
    socket.onConnect((_) {
      if (_disposed || !identical(_socket, socket)) return;
      didConnect = true;
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connections.add(AgentConnectionStatus.connected);
    });
    socket.onConnectError((error) {
      if (_disposed || !identical(_socket, socket)) return;
      final message = _stringifyError(error);
      _socket = null;
      socket.dispose();
      if (_tryNextCandidate(cookie)) return;
      _connections.add(AgentConnectionStatus.disconnected);
      _errors.add(message);
      _scheduleReconnect();
    });
    socket.onError((error) {
      if (!_disposed && identical(_socket, socket)) {
        _errors.add(_stringifyError(error));
      }
    });
    socket.onDisconnect((_) {
      if (_disposed || !didConnect || !identical(_socket, socket)) return;
      _socket = null;
      socket.dispose();
      _connections.add(AgentConnectionStatus.disconnected);
      _scheduleReconnect();
    });
    socket.on('agent_event', (data) {
      if (_disposed) return;
      final event = stringMap(data);
      if (event.isNotEmpty) _events.add(event);
    });
    _socket = socket;
    socket.connect();
  }

  bool _tryNextCandidate(String cookie) {
    if (_candidateIndex + 1 >= _serverCandidates.length) return false;
    _candidateIndex++;
    _connectCandidate(cookie);
    return true;
  }

  void _scheduleReconnect() {
    if (_disposed || !_allowReconnect || _reconnectTimer != null) return;
    final delay = agentReconnectDelay(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_disposed && _allowReconnect) unawaited(connect());
    });
  }

  void run({
    required String input,
    required String modelId,
    required String permission,
    required List<String> hostIds,
    String? sessionId,
  }) {
    _socket?.emit(
      'ws_agent_run',
      buildOpsAgentRunPayload(
        sessionId: sessionId,
        input: input,
        modelId: modelId,
        permission: permission,
        hostIds: hostIds,
      ),
    );
  }

  void stop() => _socket?.emit('ws_agent_stop');

  void approve(
    String requestId, {
    required bool approved,
    String scope = 'once',
  }) {
    _socket?.emit('ws_agent_approve', {
      'requestId': requestId,
      'approved': approved,
      'scope': scope,
    });
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

  String _stringifyError(Object? error) {
    if (error == null) return 'Connection error';
    if (error is Map) {
      final message = error['message'] ?? error['error'] ?? error['data'];
      return message?.toString() ?? error.toString();
    }
    return error.toString();
  }

  void disconnect() {
    _allowReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    if (!_disposed) _connections.add(AgentConnectionStatus.disconnected);
  }

  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _events.close();
    _connections.close();
    _errors.close();
  }
}
