import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/ui.dart';

import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';
import 'terminal_session.dart';

class TerminalSessionManager extends ChangeNotifier {
  TerminalSessionManager({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final List<TerminalSession> _sessions = [];
  String? _activeId;

  Iterable<TerminalSession> get sessions => List.unmodifiable(_sessions);
  String? get activeId => _activeId;

  TerminalSession? get activeSession {
    final id = _activeId;
    if (id == null) return null;
    return _findOrNull(id);
  }

  TerminalSession? firstForHost(String hostId) {
    for (final session in _sessions) {
      if (session.config.hostId == hostId) return session;
    }
    return null;
  }

  Future<TerminalSession> openSession(SshConnectionConfig config) async {
    final controller = SshTerminalController(config: config);
    final displayName = config.name.isEmpty
        ? '${config.username}@${config.host}'
        : config.name;
    final session = TerminalSession(
      id: _uuid.v4(),
      config: config,
      displayName: displayName,
      controller: controller,
      viewController: TerminalController(),
      scrollController: ScrollController(),
      viewKey: GlobalKey<TerminalViewState>(),
    );
    _sessions.add(session);
    _activeId = session.id;
    notifyListeners();
    unawaited(_connect(session));
    return session;
  }

  void setActive(String id) {
    if (_activeId == id || _findOrNull(id) == null) return;
    _activeId = id;
    notifyListeners();
  }

  Future<void> reconnect(String id) async {
    final session = _findOrNull(id);
    if (session == null) return;
    final terminal = session.controller.terminal;
    await session.controller.disconnect();
    session.controller = SshTerminalController(
      config: session.config,
      terminal: terminal,
    );
    session.controller.terminal.write('\r\n[Reconnecting]\r\n');
    await _connect(session);
  }

  Future<void> closeSession(String id) async {
    final index = _sessions.indexWhere((session) => session.id == id);
    if (index == -1) return;
    final session = _sessions.removeAt(index);
    await session.controller.disconnect();
    session.viewController.dispose();
    session.scrollController.dispose();
    session.status = TerminalSessionStatus.disconnected;
    if (_activeId == id) {
      _activeId = _sessions.isEmpty ? null : _sessions.first.id;
    }
    notifyListeners();
  }

  Future<void> closeAll() async {
    final copy = List<TerminalSession>.from(_sessions);
    _sessions.clear();
    _activeId = null;
    for (final session in copy) {
      await session.controller.disconnect();
      session.viewController.dispose();
      session.scrollController.dispose();
    }
    notifyListeners();
  }

  Future<void> _connect(TerminalSession session) async {
    session.status = TerminalSessionStatus.connecting;
    session.lastError = null;
    notifyListeners();
    try {
      await session.controller.connect();
      if (!_sessions.contains(session)) return;
      session.status = TerminalSessionStatus.connected;
      notifyListeners();
    } catch (error) {
      if (!_sessions.contains(session)) return;
      session.status = TerminalSessionStatus.error;
      session.lastError = error.toString();
      session.controller.terminal.write('\r\n[Error] ${session.lastError}\r\n');
      notifyListeners();
    }
  }

  TerminalSession? _findOrNull(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }
}
