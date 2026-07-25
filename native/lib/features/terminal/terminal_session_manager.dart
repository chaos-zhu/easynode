import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/ui.dart';

import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';
import 'server_status_monitor_manager.dart';
import 'terminal_session.dart';

typedef ShouldAutoStartStatusMonitor = bool Function();
typedef OnLastSessionForHostClosed = Future<void> Function(String hostId);

class TerminalSessionManager extends ChangeNotifier {
  TerminalSessionManager({
    Uuid? uuid,
    ServerStatusMonitorManager? statusMonitorManager,
    ShouldAutoStartStatusMonitor? shouldAutoStartStatusMonitor,
    OnLastSessionForHostClosed? onLastSessionForHostClosed,
  }) : _uuid = uuid ?? const Uuid(),
       _statusMonitorManager = statusMonitorManager,
       _shouldAutoStartStatusMonitor =
           shouldAutoStartStatusMonitor ?? (() => false),
       _onLastSessionForHostClosed = onLastSessionForHostClosed;

  final Uuid _uuid;
  final ServerStatusMonitorManager? _statusMonitorManager;
  final ShouldAutoStartStatusMonitor _shouldAutoStartStatusMonitor;
  final OnLastSessionForHostClosed? _onLastSessionForHostClosed;
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
    // Force-disconnect regardless of current state (connecting/connected/error).
    final oldController = session.controller;
    session.controller = SshTerminalController(
      config: session.config,
      terminal: terminal,
    );
    session.status = TerminalSessionStatus.connecting;
    notifyListeners();
    // Tear down the old controller in the background — it no longer owns the
    // terminal so its disconnect cannot interfere with the new connection.
    unawaited(oldController.disconnect());
    terminal.write('\r\n[Reconnecting]\r\n');
    await _connect(session);
  }

  Future<void> closeSession(String id) async {
    final index = _sessions.indexWhere((session) => session.id == id);
    if (index == -1) return;
    final session = _sessions.removeAt(index);
    await _detachStatusMonitor(session);
    await session.controller.disconnect();
    session.viewController.dispose();
    session.scrollController.dispose();
    session.status = TerminalSessionStatus.disconnected;
    if (_activeId == id) {
      _activeId = _sessions.isEmpty ? null : _sessions.first.id;
    }
    await _closeDependentSessionsIfLastForHost(session.config.hostId);
    notifyListeners();
  }

  Future<void> closeAll() async {
    final copy = List<TerminalSession>.from(_sessions);
    _sessions.clear();
    _activeId = null;
    final hostIds = <String>{};
    for (final session in copy) {
      hostIds.add(session.config.hostId);
      await _detachStatusMonitor(session);
      await session.controller.disconnect();
      session.viewController.dispose();
      session.scrollController.dispose();
    }
    for (final hostId in hostIds) {
      await _onLastSessionForHostClosed?.call(hostId);
    }
    notifyListeners();
  }

  Future<void> _closeDependentSessionsIfLastForHost(String hostId) async {
    if (_sessions.any((session) => session.config.hostId == hostId)) return;
    await _onLastSessionForHostClosed?.call(hostId);
  }

  Future<void> _connect(TerminalSession session) async {
    final controller = session.controller;
    session.status = TerminalSessionStatus.connecting;
    session.lastError = null;
    notifyListeners();
    try {
      await controller.connect();
      // After await, verify this controller is still the active one — a
      // concurrent reconnect may have replaced it.
      if (!_sessions.contains(session) || session.controller != controller) {
        return;
      }
      session.status = TerminalSessionStatus.connected;
      notifyListeners();
      if (_shouldAutoStartStatusMonitor()) {
        unawaited(
          _statusMonitorManager?.attach(
            sessionId: session.id,
            config: session.config,
          ),
        );
      }
    } catch (error) {
      if (!_sessions.contains(session) || session.controller != controller) {
        return;
      }
      session.status = TerminalSessionStatus.error;
      session.lastError = error.toString();
      session.controller.terminal.write('\r\n[Error] ${session.lastError}\r\n');
      // 连接失败时 SshTerminalController 还没接管 terminal.onOutput（只有 shell()
      // 成功后才会赋值），此时按键原本无处可去；这里临时接管一下，让回车触发重连。
      session.controller.terminal.onOutput = (data) {
        if (session.status == TerminalSessionStatus.error &&
            (data.contains('\r') || data.contains('\n'))) {
          unawaited(reconnect(session.id));
        }
      };
      notifyListeners();
    }
  }

  Future<void> _detachStatusMonitor(TerminalSession session) async {
    await _statusMonitorManager?.detach(
      sessionId: session.id,
      hostId: session.config.hostId,
    );
  }

  TerminalSession? _findOrNull(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }
}
