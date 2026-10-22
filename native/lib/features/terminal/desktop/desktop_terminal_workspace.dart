import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../../../state/api_providers.dart';
import '../../../state/auth_notifier.dart';
import '../../../state/desktop_server_catalog_provider.dart';
import '../../servers/server_model.dart';
import '../server_status_monitor_manager.dart';
import '../ssh_connection_config.dart';
import '../terminal_session_resources.dart';
import 'desktop_ssh_connection.dart';
import 'desktop_terminal_settings.dart';
import 'terminal_command_bridge.dart';
import 'terminal_output_highlighter.dart';

enum DesktopTerminalStatus { connecting, connected, disconnected, error }

class DesktopTerminalPane {
  DesktopTerminalPane(this.server) {
    terminal.onTitleChange = (value) => title = value;
    commands = TerminalCommandBridge(
      write: (data) => connection?.write(data),
      display: _display,
    );
  }
  final String id = const Uuid().v4();
  final ServerModel server;
  final terminal = Terminal(maxLines: 10000);
  final viewController = TerminalController();
  final scrollController = ScrollController();
  final focusNode = FocusNode();
  final viewKey = GlobalKey<TerminalViewState>();
  final highlighter = TerminalOutputHighlighter();
  late final TerminalCommandBridge commands;
  DesktopTerminalConnection? connection;
  SshConnectionConfig? config;
  DesktopTerminalStatus status = DesktopTerminalStatus.connecting;
  String? error;
  String title = '';
  String scriptDraft = '';
  Duration? latency;
  final List<double> latencyHistory = [];
  Timer? reconnectTimer;
  Timer? pingTimer;
  bool closed = false;
  bool aiMounted = false;
  final aiPrefill = ValueNotifier<String>('');
  void _display(String data) => terminal.write(highlighter.process(data));
  String get output => [
    for (var i = 0; i < terminal.buffer.lines.length; i++)
      terminal.buffer.lines[i].getText(
        0,
        terminal.buffer.lines[i].getTrimmedLength(),
      ),
  ].join('\n');

  Future<void> disconnect() async {
    reconnectTimer?.cancel();
    pingTimer?.cancel();
    commands.disconnect();
    final previous = connection;
    connection = null;
    await previous?.close();
  }

  void dispose() {
    closed = true;
    unawaited(disconnect());
    terminal.onOutput = null;
    terminal.onResize = null;
    viewController.dispose();
    scrollController.dispose();
    focusNode.dispose();
    aiPrefill.dispose();
  }
}

class DesktopTerminalTab {
  DesktopTerminalTab(this.server) : panes = [DesktopTerminalPane(server)];
  final String id = const Uuid().v4();
  final ServerModel server;
  final List<DesktopTerminalPane> panes;
  String? activePaneId;
  bool horizontal = false;
  bool vertical = false;
  bool syncInput = false;
  DesktopTerminalPane get activePane =>
      panes.where((p) => p.id == activePaneId).firstOrNull ?? panes.first;
  DesktopTerminalStatus get status =>
      panes.any((p) => p.status == DesktopTerminalStatus.connected)
      ? DesktopTerminalStatus.connected
      : panes.first.status;
}

/// Owns connections, not widgets: changing page/tab/layout never reconnects.
class DesktopTerminalWorkspace extends ChangeNotifier {
  DesktopTerminalWorkspace({
    required this.loadConfig,
    required this.settings,
    DesktopTerminalConnection Function()? connectionFactory,
    ServerStatusMonitorManager? monitor,
    TerminalSessionResources? resources,
    this.onConnected,
  }) : _connectionFactory = connectionFactory ?? DesktopSshConnection.new,
       monitor = monitor ?? ServerStatusMonitorManager(),
       resources = resources ?? TerminalSessionResources();

  final Future<SshConnectionConfig> Function(String) loadConfig;
  final DesktopTerminalSettings Function() settings;
  final DesktopTerminalConnection Function() _connectionFactory;
  final Future<void> Function(ServerModel)? onConnected;
  final ServerStatusMonitorManager monitor;
  final TerminalSessionResources resources;
  final _tabs = <DesktopTerminalTab>[];
  UnmodifiableListView<DesktopTerminalTab> get tabs =>
      UnmodifiableListView(_tabs);
  String? activeTabId;
  bool syncAll = false;
  bool _disposed = false;
  DesktopTerminalTab? get activeTab =>
      _tabs.where((t) => t.id == activeTabId).firstOrNull ?? _tabs.firstOrNull;
  List<DesktopTerminalPane> get panes => _tabs.expand((t) => t.panes).toList();
  void changed() {
    if (!_disposed) notifyListeners();
  }

  DesktopTerminalTab open(ServerModel server) {
    if (!server.canConnect || server.isWindows) {
      throw StateError('SSH is not configured');
    }
    final tab = DesktopTerminalTab(server);
    _tabs.add(tab);
    activeTabId = tab.id;
    _wire(tab, tab.panes.first);
    changed();
    unawaited(reconnect(tab.panes.first));
    return tab;
  }

  void activate(DesktopTerminalTab tab, [DesktopTerminalPane? pane]) {
    activeTabId = tab.id;
    if (pane != null) tab.activePaneId = pane.id;
    changed();
  }

  void _wire(DesktopTerminalTab tab, DesktopTerminalPane pane) {
    pane.terminal.onOutput = (data) => input(pane, data);
    pane.terminal.onResize = (cols, rows, _, _) =>
        pane.connection?.resize(cols, rows);
  }

  void input(
    DesktopTerminalPane origin,
    String data, {
    bool synchronize = true,
  }) {
    if (origin.status != DesktopTerminalStatus.connected) {
      if (data == '\r' || data == '\n') unawaited(reconnect(origin));
      return;
    }
    final tab = _tabs.where((t) => t.panes.contains(origin)).firstOrNull;
    final targets = !synchronize
        ? [origin]
        : syncAll
        ? panes
        : tab?.syncInput == true
        ? tab!.panes
        : [origin];
    for (final pane in targets) {
      if (pane.status == DesktopTerminalStatus.connected) {
        pane.connection?.write(data);
      }
    }
  }

  Future<Map<String, dynamic>> executeAi(
    DesktopTerminalPane pane,
    String command,
    String requestId, {
    void Function(Map<String, dynamic>)? onProgress,
  }) {
    if (pane.status != DesktopTerminalStatus.connected || pane.closed) {
      return Future.value({'ok': false, 'error': '当前终端未连接'});
    }
    // Tool commands belong to one PTY; never broadcast through sync input.
    return pane.commands.execute(command, requestId, onProgress: onProgress);
  }

  Future<void> reconnect(DesktopTerminalPane pane) async {
    if (pane.closed ||
        _disposed ||
        (pane.connection != null &&
            pane.status == DesktopTerminalStatus.connecting)) {
      return;
    }
    await pane.disconnect();
    if (pane.closed || _disposed) return;
    pane.status = DesktopTerminalStatus.connecting;
    pane.error = null;
    pane.highlighter.reset();
    changed();
    final connection = _connectionFactory();
    pane.connection = connection;
    try {
      final config = await loadConfig(pane.server.id);
      if (pane.closed || !identical(pane.connection, connection)) return;
      pane.config = config;
      await connection.connect(
        config,
        columns: pane.terminal.viewWidth,
        rows: pane.terminal.viewHeight,
        onData: pane.commands.output,
        onClosed: (error) => _disconnected(pane, error),
      );
      if (pane.closed ||
          !identical(pane.connection, connection) ||
          pane.status != DesktopTerminalStatus.connecting) {
        return;
      }
      pane.status = DesktopTerminalStatus.connected;
      connection.resize(pane.terminal.viewWidth, pane.terminal.viewHeight);
      if (pane.server.command.isNotEmpty) {
        connection.write('${pane.server.command}\n');
      }
      unawaited(monitor.attach(sessionId: pane.id, config: config));
      pane.pingTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _ping(pane, connection),
      );
      unawaited(_ping(pane, connection));
      changed();
      try {
        await onConnected?.call(pane.server);
      } catch (_) {
        /* History is optional; SSH stays connected. */
      }
    } catch (error) {
      if (pane.closed || _disposed) return;
      await pane.disconnect();
      pane.status = DesktopTerminalStatus.error;
      pane.error = error.toString();
      pane.terminal.write('\r\n\x1b[31m$error\x1b[0m\r\n');
      changed();
    }
  }

  Future<void> _ping(
    DesktopTerminalPane pane,
    DesktopTerminalConnection connection,
  ) async {
    try {
      final latency = await connection.ping().timeout(
        const Duration(seconds: 4),
      );
      if (pane.closed || !identical(pane.connection, connection)) return;
      pane.latency = latency;
      pane.latencyHistory.add(latency.inMilliseconds.toDouble());
      if (pane.latencyHistory.length > 60) pane.latencyHistory.removeAt(0);
      changed();
    } catch (_) {
      /* Shell closure owns reconnect; latency failure does not. */
    }
  }

  void _disconnected(DesktopTerminalPane pane, Object? error) {
    if (pane.closed || _disposed) return;
    pane.status = DesktopTerminalStatus.disconnected;
    pane.error = error?.toString();
    pane.commands.disconnect();
    pane.pingTimer?.cancel();
    pane.terminal.write('\r\n\x1b[33m[Disconnected]\x1b[0m\r\n');
    if (settings().autoReconnect) {
      pane.reconnectTimer = Timer(
        const Duration(seconds: 3),
        () => unawaited(reconnect(pane)),
      );
    }
    changed();
  }

  void toggleSplit(DesktopTerminalTab tab, {required bool horizontal}) {
    if (horizontal) {
      tab.horizontal = !tab.horizontal;
    } else {
      tab.vertical = !tab.vertical;
    }
    final count = (tab.horizontal ? 2 : 1) * (tab.vertical ? 2 : 1);
    while (tab.panes.length > count) {
      _removePane(tab, tab.panes.last);
    }
    while (tab.panes.length < count) {
      final pane = DesktopTerminalPane(tab.server);
      tab.panes.add(pane);
      _wire(tab, pane);
      unawaited(reconnect(pane));
    }
    changed();
  }

  void _removePane(DesktopTerminalTab tab, DesktopTerminalPane pane) {
    tab.panes.remove(pane);
    unawaited(monitor.detach(sessionId: pane.id, hostId: pane.server.id));
    pane.dispose();
  }

  void closePane(DesktopTerminalTab tab, DesktopTerminalPane pane) {
    if (tab.panes.length == 1) {
      closeTab(tab);
      return;
    }
    _removePane(tab, pane);
    if (tab.panes.length == 1) {
      tab.horizontal = false;
      tab.vertical = false;
    }
    changed();
  }

  void closeTab(DesktopTerminalTab tab) {
    if (!_tabs.remove(tab)) return;
    for (final pane in [...tab.panes]) {
      _removePane(tab, pane);
    }
    if (!_tabs.any((t) => t.server.id == tab.server.id)) {
      unawaited(resources.disposeHost(tab.server.id));
    }
    if (activeTabId == tab.id) activeTabId = _tabs.lastOrNull?.id;
    changed();
  }

  void closeOthers(DesktopTerminalTab tab) {
    for (final other in [..._tabs]) {
      if (other != tab) closeTab(other);
    }
  }

  void closeAll() {
    for (final tab in [..._tabs]) {
      closeTab(tab);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pane in panes) {
      pane.dispose();
    }
    _tabs.clear();
    monitor.dispose();
    resources.dispose();
    super.dispose();
  }
}

final desktopTerminalWorkspaceProvider =
    Provider.autoDispose<DesktopTerminalWorkspace>((ref) {
      // Releasing the authenticated desktop shell releases every local connection.
      ref.watch(authProvider.select((state) => state.session));
      final repository = ref.watch(serverRepositoryProvider);
      final api = ref.watch(apiClientProvider);
      final workspace = DesktopTerminalWorkspace(
        loadConfig: repository.fetchSshConfig,
        settings: () => ref.read(effectiveDesktopTerminalSettingsProvider),
        onConnected: (host) async {
          await api.postJson('/host-last-connect', {'id': host.id});
          ref.invalidate(desktopServerCatalogProvider);
        },
      );
      ref.onDispose(workspace.dispose);
      return workspace;
    });
