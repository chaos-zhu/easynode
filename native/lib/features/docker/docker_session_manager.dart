import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/api/cookie_store.dart';
import '../auth/auth_session.dart';
import '../servers/server_model.dart';
import 'docker_container.dart';
import 'docker_socket_client.dart';

enum DockerConnectionStatus { connecting, connected, disconnected, error }

class DockerSessionState {
  DockerSessionState({
    required this.server,
    required this.client,
    this.status = DockerConnectionStatus.connecting,
    this.containers = const [],
    this.logs = '',
    this.errorMessage,
    this.loading = true,
    this.refreshing = false,
  });

  final ServerModel server;
  final DockerSocketClient client;
  DockerConnectionStatus status;
  List<DockerContainer> containers;
  String logs;
  String? errorMessage;
  bool loading;
  bool refreshing;
  final Set<String> operatingIds = {};
}

class DockerSessionManager extends ChangeNotifier {
  final Map<String, DockerSessionState> _sessions = {};
  final Map<String, List<StreamSubscription<dynamic>>> _subscriptions = {};
  String? _activeHostId;

  List<DockerSessionState> get sessions =>
      _sessions.values.toList(growable: false);

  DockerSessionState? get activeSession {
    final id = _activeHostId;
    if (id == null) return null;
    return _sessions[id];
  }

  DockerSessionState? sessionFor(String? hostId) {
    if (hostId == null || hostId.isEmpty) return null;
    return _sessions[hostId];
  }

  String? get activeHostId => _activeHostId;

  bool isConnected(String hostId) =>
      _sessions[hostId]?.status == DockerConnectionStatus.connected;

  Future<void> connect({
    required ServerModel server,
    required AuthSession authSession,
    required SessionCookieStore cookieStore,
  }) async {
    final existing = _sessions[server.id];
    if (existing != null) {
      _activeHostId = server.id;
      if (existing.status == DockerConnectionStatus.disconnected ||
          existing.status == DockerConnectionStatus.error) {
        existing.status = DockerConnectionStatus.connecting;
        existing.loading = true;
        existing.errorMessage = null;
        notifyListeners();
        await existing.client.connect();
      } else {
        notifyListeners();
      }
      return;
    }

    final client = DockerSocketClient(
      authSession: authSession,
      cookieStore: cookieStore,
      hostId: server.id,
    );
    final session = DockerSessionState(server: server, client: client);
    _sessions[server.id] = session;
    _activeHostId = server.id;
    _subscriptions[server.id] = [
      client.connectedStream.listen((connected) {
        if (connected) {
          session.status = DockerConnectionStatus.connected;
        } else {
          if (session.status == DockerConnectionStatus.connecting) return;
          session.status = DockerConnectionStatus.disconnected;
          session.loading = false;
        }
        notifyListeners();
      }),
      client.containersStream.listen((containers) {
        session.containers = containers;
        session.loading = false;
        session.refreshing = false;
        session.operatingIds.clear();
        session.errorMessage = null;
        session.status = DockerConnectionStatus.connected;
        notifyListeners();
      }),
      client.logsStream.listen((logs) {
        session.logs = logs;
        notifyListeners();
      }),
      client.operationStream.listen((result) {
        if (!result.success) {
          session.operatingIds.clear();
          session.errorMessage = result.message;
        }
        session.loading = false;
        notifyListeners();
        if (result.success) client.refresh();
      }),
      client.errorStream.listen((message) {
        session.status = DockerConnectionStatus.error;
        session.loading = false;
        session.refreshing = false;
        session.errorMessage = message;
        notifyListeners();
      }),
    ];
    notifyListeners();
    await client.connect();
  }

  void activate(String hostId) {
    if (!_sessions.containsKey(hostId)) return;
    _activeHostId = hostId;
    notifyListeners();
  }

  void refreshActive() {
    final session = activeSession;
    _refreshSession(session);
  }

  void refresh(String hostId) {
    _refreshSession(sessionFor(hostId));
  }

  void _refreshSession(DockerSessionState? session) {
    if (session == null) return;
    session.refreshing = true;
    session.errorMessage = null;
    notifyListeners();
    session.client.refresh();
  }

  void reconnectActive() {
    final session = activeSession;
    _reconnectSession(session);
  }

  void reconnect(String hostId) {
    _reconnectSession(sessionFor(hostId));
  }

  void _reconnectSession(DockerSessionState? session) {
    if (session == null) return;
    session.status = DockerConnectionStatus.connecting;
    session.loading = true;
    session.errorMessage = null;
    notifyListeners();
    unawaited(session.client.connect());
  }

  void getLogs(DockerContainer container, {String? hostId}) {
    final session = hostId == null ? activeSession : sessionFor(hostId);
    if (session == null) return;
    session.logs = '';
    notifyListeners();
    session.client.getLogs(container.id);
  }

  void refreshLogs(DockerContainer container, {String? hostId}) {
    final session = hostId == null ? activeSession : sessionFor(hostId);
    session?.client.getLogs(container.id);
  }

  void start(DockerContainer container, {String? hostId}) =>
      _operate(container, (client) {
        client.start(container.id);
      }, hostId: hostId);

  void stop(DockerContainer container, {String? hostId}) =>
      _operate(container, (client) {
        client.stop(container.id);
      }, hostId: hostId);

  void restart(DockerContainer container, {String? hostId}) =>
      _operate(container, (client) {
        client.restart(container.id);
      }, hostId: hostId);

  void delete(DockerContainer container, {String? hostId}) =>
      _operate(container, (client) {
        client.delete(container.id);
      }, hostId: hostId);

  void _operate(
    DockerContainer container,
    void Function(DockerSocketClient client) send, {
    String? hostId,
  }) {
    final session = hostId == null ? activeSession : sessionFor(hostId);
    if (session == null) return;
    session.operatingIds.add(container.id);
    session.errorMessage = null;
    notifyListeners();
    send(session.client);
  }

  void disconnectActive() {
    final id = _activeHostId;
    if (id == null) return;
    disconnect(id);
  }

  void disconnect(String hostId) {
    final wasActive = _activeHostId == hostId;
    _disconnect(hostId);
    if (wasActive) {
      _activeHostId = _sessions.keys.isEmpty ? null : _sessions.keys.first;
    }
    notifyListeners();
  }

  void _disconnect(String hostId) {
    final session = _sessions.remove(hostId);
    if (session == null) return;
    for (final sub in _subscriptions.remove(hostId) ?? const []) {
      sub.cancel();
    }
    session.client.disconnect();
  }

  void _disconnectAll() {
    for (final hostId in _sessions.keys.toList(growable: false)) {
      _disconnect(hostId);
    }
    _activeHostId = null;
  }

  @override
  void dispose() {
    _disconnectAll();
    super.dispose();
  }
}
