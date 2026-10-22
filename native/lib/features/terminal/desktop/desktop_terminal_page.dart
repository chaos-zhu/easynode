import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../core/ui/desktop_management.dart';
import '../../../core/ui/desktop_popover.dart';
import '../../../state/desktop_server_catalog_provider.dart';
import '../../scripts/script_model.dart';
import 'desktop_sftp_panel.dart';
import 'desktop_docker_panel.dart';
import '../../../state/plus_info_notifier.dart';
import '../../servers/desktop_server_form_dialog.dart';
import '../../servers/server_model.dart';
import '../terminal_script_command.dart';
import 'desktop_terminal_agent.dart';
import 'desktop_terminal_grid.dart';
import 'desktop_terminal_pane.dart';
import 'desktop_terminal_scripts.dart';
import 'desktop_terminal_settings.dart';
import 'desktop_terminal_settings_dialog.dart';
import 'desktop_terminal_status.dart';
import 'desktop_terminal_workspace.dart';
import 'terminal_widgets.dart';
import 'terminal_catalog_order.dart';
import 'terminal_catalog_menu.dart';

class DesktopTerminalPage extends ConsumerStatefulWidget {
  const DesktopTerminalPage({super.key, this.onFullscreenChanged});
  final ValueChanged<bool>? onFullscreenChanged;
  @override
  ConsumerState<DesktopTerminalPage> createState() =>
      _DesktopTerminalPageState();
}

class _DesktopTerminalPageState extends ConsumerState<DesktopTerminalPage> {
  bool _grid = false,
      _horizontalGrid = false,
      _status = true,
      _sftp = false,
      _ai = false,
      _scripts = false,
      _fullscreen = false;
  bool _preferencesLoaded = false, _scriptsMounted = false;
  double _visibleSideWidth = 450;
  final _workspaceScroll = ScrollController();
  double _sftpWidth = 450, _aiWidth = 450, _footerHeight = 250;
  final _sftpMounted = <String>{};
  final _sftpPaths = <String, ValueNotifier<String?>>{};
  final _paneKeys = <String, GlobalKey>{};
  DesktopTerminalWorkspace get workspace =>
      ref.read(desktopTerminalWorkspaceProvider);

  @override
  void dispose() {
    _workspaceScroll.dispose();
    for (final request in _sftpPaths.values) {
      request.dispose();
    }
    super.dispose();
  }

  void _preference(String key, Object value) {
    unawaited(
      ref
          .read(desktopTerminalPreferencesProvider.notifier)
          .set(key, value)
          .catchError((Object error) {
            if (mounted) terminalNotice(context, error.toString());
          }),
    );
  }

  void _initializePreferences(Map<String, dynamic> prefs) {
    if (_preferencesLoaded) return;
    _preferencesLoaded = true;
    _grid = prefs['grid'] == true;
    _horizontalGrid = prefs['horizontalGrid'] == true;
    _status = prefs['status'] != false;
    _scripts = prefs['scripts'] == true;
    _scriptsMounted = _scripts;
    _sftpWidth = (prefs['sftpWidth'] as num?)?.toDouble() ?? 450;
    _aiWidth = (prefs['aiWidth'] as num?)?.toDouble() ?? 450;
    _footerHeight = (prefs['footerHeight'] as num?)?.toDouble() ?? 250;
  }

  void _connect(ServerModel server) {
    if (!server.canConnect || server.isWindows) {
      unawaited(_editServer(server));
      return;
    }
    workspace.open(server).activePane.focusNode.requestFocus();
  }

  Future<void> _editServer(ServerModel server) async {
    final catalog = await ref.read(desktopServerCatalogProvider.future);
    if (!mounted) return;
    await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DesktopServerFormDialog(server: server, catalog: catalog),
    );
    ref.invalidate(desktopServerCatalogProvider);
  }

  void _sendScript(String command, bool base64) =>
      _sendScriptTo(workspace.activeTab?.activePane, command, base64);

  void _sendScriptTo(
    DesktopTerminalPane? pane,
    String command,
    bool base64, {
    bool synchronize = true,
  }) {
    if (pane == null || pane.status != DesktopTerminalStatus.connected) {
      terminalNotice(context, dt(context, 'notConnected'));
      return;
    }
    workspace.input(
      pane,
      formatTerminalScriptCommand(
        command,
        useBase64: base64,
        appendNewline: ref
            .read(effectiveDesktopTerminalSettingsProvider)
            .autoExecute,
      ),
      synchronize: synchronize,
    );
  }

  void _activate(DesktopTerminalTab tab, [DesktopTerminalPane? pane]) {
    workspace.activate(tab, pane);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !tab.activePane.closed && !_ai) {
        tab.activePane.focusNode.requestFocus();
      }
    });
  }

  Future<void> _paneScripts(DesktopTerminalTab tab, DesktopTerminalPane pane) {
    workspace.activate(tab, pane);
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) => DesktopManagementDialog(
        title: '${dt(context, 'longCommand')} · ${pane.server.displayName}',
        width: 900,
        body: SizedBox(
          height: MediaQuery.sizeOf(context).height * .5,
          child: DesktopTerminalScripts(
            initialDraft: pane.scriptDraft,
            onDraftChanged: (value) => pane.scriptDraft = value,
            onSend: (command, base64) {
              _sendScriptTo(pane, command, base64, synchronize: false);
              Navigator.pop(dialogContext);
            },
          ),
        ),
        actions: const [],
      ),
    );
  }

  void _showAi(DesktopTerminalPane pane, [String prefill = '']) {
    pane.aiMounted = true;
    if (prefill.isNotEmpty) pane.aiPrefill.value = prefill;
    setState(() {
      _ai = true;
      _sftp = false;
    });
  }

  Future<void> _syncPath(DesktopTerminalPane pane, String path) async {
    final request = _sftpPaths.putIfAbsent(
      pane.server.id,
      () => ValueNotifier<String?>(null),
    );
    setState(() {
      _sftp = true;
      _ai = false;
      _grid = false;
      _sftpMounted.add(pane.server.id);
    });
    // The panel owns connection setup and applies this path after connecting.
    request.value = null;
    request.value = path;
  }

  Future<void> _docker(DesktopTerminalTab tab) => showAppDialog<void>(
    context: context,
    builder: (_) => Dialog(
      constraints: const BoxConstraints(maxWidth: 1120),
      backgroundColor: context.colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Docker · ${tab.server.displayName}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DesktopDockerPanel(
                server: tab.server,
                manager: workspace.resources.dockerForHost(tab.server.id),
                onExecCommand: (command) => workspace.input(
                  tab.activePane,
                  '$command\n',
                  synchronize: false,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void _fullscreenToggle() {
    setState(() => _fullscreen = !_fullscreen);
    widget.onFullscreenChanged?.call(_fullscreen);
  }

  Future<void> _hostPicker(BuildContext anchor) async {
    ref.invalidate(desktopServerCatalogProvider);
    final selected = await showDesktopPopover<List<ServerModel>>(
      context: anchor,
      width: 600,
      shrinkWrapWidth: true,
      maxHeight: MediaQuery.sizeOf(context).height * .5,
      builder: (_) => const _TerminalHostPicker(),
    );
    if (!mounted || selected == null) return;
    if (selected.isEmpty) {
      terminalNotice(context, dt(context, 'configureSsh'));
      return;
    }
    for (final server in selected) {
      _connect(server);
    }
  }

  Future<void> _scriptPicker(BuildContext anchor) async {
    if (!ref.read(isPlusActiveProvider)) {
      terminalNotice(context, dt(context, 'plusRequired'));
      return;
    }
    ref.invalidate(desktopTerminalScriptCatalogProvider);
    final selected = await showDesktopPopover<(String, bool)>(
      context: anchor,
      width: 600,
      shrinkWrapWidth: true,
      maxHeight: MediaQuery.sizeOf(context).height * .5,
      builder: (_) => const _TerminalScriptPicker(),
    );
    if (mounted && selected != null) _sendScript(selected.$1, selected.$2);
  }

  Future<void> _tabMenu(DesktopTerminalTab tab, Offset position) async {
    final value = await showTerminalMenu(context, [
      TerminalMenuAction('reconnect', dt(context, 'reconnect'), Icons.refresh),
      TerminalMenuAction(
        'others',
        dt(context, 'closeOthers'),
        Icons.tab_unselected,
        enabled: workspace.tabs.length > 1,
      ),
      TerminalMenuAction(
        'all',
        dt(context, 'closeAll'),
        Icons.close_fullscreen,
      ),
    ], position: position);
    if (!mounted) return;
    switch (value) {
      case 'reconnect':
        await workspace.reconnect(tab.activePane);
      case 'others':
        workspace.closeOthers(tab);
      case 'all':
        workspace.closeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(desktopTerminalWorkspaceProvider);
    final preferences = ref.watch(desktopTerminalPreferencesProvider);
    _initializePreferences(preferences);
    // Settings failures are visible and retryable; they never stop SSH input.
    final settingsState = ref.watch(desktopTerminalSettingsProvider);
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final tab = manager.activeTab;
        _paneKeys.removeWhere((id, _) => !manager.panes.any((p) => p.id == id));
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f11): _fullscreenToggle,
            if (_fullscreen)
              const SingleActivator(LogicalKeyboardKey.escape):
                  _fullscreenToggle,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tab != null) _toolbar(tab, preferences),
              if (settingsState.hasError)
                Container(
                  color: context.colors.warning.withValues(alpha: .10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dt(context, 'settingsLoadFailed'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(desktopTerminalSettingsProvider),
                        child: Text(dt(context, 'retry')),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: tab == null
                    ? _recent()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_grid) _tabs(manager),
                          if (!_grid) _sessionTools(tab),
                          Expanded(child: _workspaceArea(manager, tab)),
                          if (_scriptsMounted)
                            Visibility(
                              visible: _scripts && !_grid,
                              maintainState: true,
                              child: SizedBox(
                                height: math.min(
                                  _footerHeight,
                                  MediaQuery.sizeOf(context).height * .48,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _resizeHandle(
                                      vertical: false,
                                      onDrag: (delta) => setState(
                                        () => _footerHeight =
                                            (_footerHeight - delta).clamp(
                                              180,
                                              MediaQuery.sizeOf(
                                                    context,
                                                  ).height *
                                                  .48,
                                            ),
                                      ),
                                      onEnd: () => _preference(
                                        'footerHeight',
                                        _footerHeight,
                                      ),
                                    ),
                                    Expanded(
                                      child: DesktopTerminalScripts(
                                        onSend: _sendScript,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _workspaceArea(
    DesktopTerminalWorkspace manager,
    DesktopTerminalTab tab,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final showStatus = !_grid && _status;
      final showSftp = !_grid && _sftp;
      final showSide = showSftp || _ai;
      final statusWidth = showStatus ? 250.0 : 0.0;
      final width = math.max(
        constraints.maxWidth,
        statusWidth + 300 + (showSide ? 328 : 0),
      );
      _visibleSideWidth = math
          .min(showSftp ? _sftpWidth : _aiWidth, width - statusWidth - 308)
          .clamp(320, 900);
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: const Key('terminal-workarea-scroll'),
          controller: _workspaceScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showStatus)
                  SizedBox(
                    width: 250,
                    child: DesktopTerminalStatusPanel(
                      key: ValueKey('status-${tab.server.id}'),
                      pane: tab.activePane,
                      monitor: manager.monitor,
                    ),
                  ),
                Expanded(
                  child: _workspaceBackground(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _terminalLayout(manager)),
                        if (!_grid &&
                            !_status &&
                            ref
                                .watch(effectiveDesktopTerminalSettingsProvider)
                                .statusBar)
                          DesktopTerminalStatusBar(
                            pane: tab.activePane,
                            monitor: manager.monitor,
                          ),
                      ],
                    ),
                  ),
                ),
                _auxiliarySftp(manager, tab),
                _auxiliaryAi(manager, tab),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _toolbar(
    DesktopTerminalTab? tab,
    Map<String, dynamic> preferences,
  ) => Container(
    key: const Key('terminal-toolbar'),
    height: 30,
    color: context.colors.chip,
    padding: const EdgeInsets.only(left: 10, right: 5),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Builder(
                    builder: (anchor) => TerminalMenuButton(
                      label: dt(context, 'connect'),
                      dropdown: true,
                      onPressed: () => _hostPicker(anchor),
                    ),
                  ),
                  if (preferences['scriptLibrary'] != false)
                    Builder(
                      builder: (anchor) => TerminalMenuButton(
                        label: dt(context, 'scripts'),
                        dropdown: true,
                        onPressed: tab == null
                            ? null
                            : () => _scriptPicker(anchor),
                      ),
                    ),
                  TerminalMenuButton(
                    label: dt(context, 'settingsMenu'),
                    onPressed: () => showDesktopTerminalSettings(context),
                  ),
                  TerminalMenuButton(
                    key: const Key('terminal-fullscreen'),
                    label: dt(
                      context,
                      _fullscreen ? 'exitFullscreen' : 'fullscreen',
                    ),
                    onPressed: _fullscreenToggle,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .75),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TerminalToggle(
                    label: dt(context, 'syncToggle'),
                    tooltip: dt(context, 'syncAll'),
                    value: workspace.syncAll,
                    onChanged: () {
                      workspace.syncAll = !workspace.syncAll;
                      workspace.changed();
                    },
                  ),
                  if (!_grid)
                    TerminalToggle(
                      key: const Key('terminal-command-toggle'),
                      label: dt(context, 'commandToggle'),
                      tooltip: dt(context, 'longCommand'),
                      value: _scripts,
                      onChanged: () {
                        setState(() {
                          _scripts = !_scripts;
                          _scriptsMounted = true;
                        });
                        _preference('scripts', _scripts);
                      },
                    ),
                  TerminalToggle(
                    key: const Key('terminal-layout-toggle'),
                    label: dt(context, _grid ? 'singleWindow' : 'multiWindow'),
                    tooltip: dt(context, _grid ? 'tabs' : 'grid'),
                    activeColor: context.colors.accent,
                    inactiveColor: context.colors.success,
                    value: _grid,
                    onChanged: () {
                      setState(() {
                        _grid = !_grid;
                      });
                      _preference('grid', _grid);
                    },
                  ),
                  if (_grid && workspace.panes.length > 4)
                    TerminalLayoutSelector(
                      horizontal: _horizontalGrid,
                      onChanged: (horizontal) {
                        setState(() => _horizontalGrid = horizontal);
                        _preference('horizontalGrid', horizontal);
                      },
                    ),
                  if (_grid && tab != null)
                    TerminalToolButton(
                      icon: Icons.chat_bubble_outline,
                      label: dt(context, 'ai'),
                      showLabel: false,
                      selected: _ai,
                      onPressed: () => _ai
                          ? setState(() => _ai = false)
                          : _showAi(tab.activePane),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _tabs(DesktopTerminalWorkspace manager) => SizedBox(
    height: 32,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.chip,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in manager.tabs)
            GestureDetector(
              onSecondaryTapUp: (details) =>
                  _tabMenu(tab, details.globalPosition),
              child: Material(
                color: manager.activeTab == tab
                    ? context.colors.card
                    : context.colors.chip,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: context.colors.border),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _activate(tab),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          _statusDot(tab.status),
                          const SizedBox(width: 7),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              tab.server.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: manager.activeTab == tab
                                    ? context.colors.accent
                                    : context.colors.text,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => manager.closeTab(tab),
                            tooltip: dt(context, 'close'),
                            icon: const Icon(Icons.close, size: 13),
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _statusDot(DesktopTerminalStatus status) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (status) {
        DesktopTerminalStatus.connected => context.colors.success,
        DesktopTerminalStatus.connecting => context.colors.warning,
        _ => context.colors.danger,
      },
    ),
  );
  Widget _sessionTools(DesktopTerminalTab tab) => Container(
    key: const Key('terminal-session-tools'),
    height: 30,
    decoration: BoxDecoration(
      color: context.colors.card,
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.monitor_heart_outlined,
            label: dt(context, 'status'),
            selected: _status,
            onPressed: () {
              setState(() => _status = !_status);
              _preference('status', _status);
            },
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.folder_open_outlined,
            label: 'SFTP',
            selected: _sftp,
            onPressed: () => setState(() {
              _sftp = !_sftp;
              if (_sftp) {
                _ai = false;
                _sftpMounted.add(tab.server.id);
              }
            }),
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.chat_bubble_outline,
            label: dt(context, 'ai'),
            selected: _ai,
            onPressed: () {
              if (_ai) {
                setState(() => _ai = false);
              } else {
                _showAi(tab.activePane);
              }
            },
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.layers_outlined,
            label: 'Docker',
            onPressed: () => _docker(tab),
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.sync_alt,
            label: dt(context, 'syncSplit'),
            selected: tab.syncInput,
            onPressed: () {
              tab.syncInput = !tab.syncInput;
              workspace.changed();
            },
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.vertical_split_outlined,
            label: dt(context, 'splitHorizontal'),
            selected: tab.horizontal,
            onPressed: () => workspace.toggleSplit(tab, horizontal: true),
          ),
          TerminalToolButton(
            showLabel: false,
            width: 46,
            icon: Icons.horizontal_split_outlined,
            label: dt(context, 'splitVertical'),
            selected: tab.vertical,
            onPressed: () => workspace.toggleSplit(tab, horizontal: false),
          ),
        ],
      ),
    ),
  );
  Widget _workspaceBackground(Widget child) {
    final settings = ref.watch(effectiveDesktopTerminalSettingsProvider);
    final image = ref.watch(desktopTerminalImagePreviewProvider);
    final asset = settings.background['assetId'] as String?;
    final bytes =
        image ??
        (asset == null
            ? null
            : ref.watch(desktopTerminalBackgroundProvider(asset)).valueOrNull);
    final imageMode = settings.background['mode'] == 'image';
    final theme = desktopTerminalTheme(
      settings,
      ref.watch(desktopTerminalThemesProvider).valueOrNull ?? {},
    );
    final fit =
        {
          'cover': BoxFit.cover,
          'contain': BoxFit.contain,
          'fill': BoxFit.fill,
        }[settings.background['fit']] ??
        BoxFit.cover;
    final alignment =
        {
          'center': Alignment.center,
          'top': Alignment.topCenter,
          'bottom': Alignment.bottomCenter,
          'left': Alignment.centerLeft,
          'right': Alignment.centerRight,
        }[settings.background['position']] ??
        Alignment.center;
    final overlay = terminalMap(settings.background['overlay']);
    final light =
        overlay['tone'] == 'light' ||
        overlay['tone'] == 'auto' && theme.foreground.computeLuminance() < .45;
    return ColoredBox(
      color: theme.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageMode && bytes != null)
            Image.memory(
              bytes,
              fit: fit,
              alignment: alignment,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) =>
                  Center(child: Text(dt(context, 'imageLoadFailed'))),
            ),
          if (imageMode && bytes != null)
            ColoredBox(
              color: (light ? Colors.white : Colors.black).withValues(
                alpha: (overlay['opacity'] as num?)?.toDouble() ?? .35,
              ),
            ),
          child,
        ],
      ),
    );
  }

  Widget _paneView(DesktopTerminalTab tab, DesktopTerminalPane pane) =>
      DesktopTerminalPaneView(
        key: _paneKeys.putIfAbsent(pane.id, GlobalKey.new),
        pane: pane,
        workspace: workspace,
        onFocus: () => workspace.activate(tab, pane),
        onClose: () => workspace.closePane(tab, pane),
        onFullscreen: _fullscreenToggle,
        onExitFullscreen: _fullscreen ? _fullscreenToggle : null,
        onAi: (text) {
          workspace.activate(tab, pane);
          _showAi(pane, text);
        },
        onSyncPath: (path) => _syncPath(pane, path),
        sftpVisible: _sftp,
      );

  Widget _terminalLayout(DesktopTerminalWorkspace manager) {
    if (!_grid) {
      return IndexedStack(
        index: manager.tabs.indexOf(manager.activeTab!),
        children: [
          for (final tab in manager.tabs)
            ExcludeFocus(
              excluding: manager.activeTab != tab,
              child: _tabPanes(tab),
            ),
        ],
      );
    }
    return DesktopTerminalGrid(
      workspace: manager,
      horizontal: _horizontalGrid,
      showStatusBar: ref
          .watch(effectiveDesktopTerminalSettingsProvider)
          .statusBar,
      paneBuilder: _paneView,
      onActivate: (tab, pane) => _activate(tab, pane),
      onContextMenu: (tab, position) => _tabMenu(tab, position),
      onScripts: (tab, pane) => _paneScripts(tab, pane),
    );
  }

  Widget _tabPanes(DesktopTerminalTab tab) {
    final columns = tab.horizontal ? 2 : 1;
    final rows = (tab.panes.length / columns).ceil();
    return Column(
      children: [
        for (var y = 0; y < rows; y++)
          Expanded(
            child: Row(
              children: [
                for (var x = 0; x < columns; x++)
                  Expanded(
                    child: y * columns + x < tab.panes.length
                        ? Container(
                            decoration: BoxDecoration(
                              border: _splitBorder(tab, y * columns + x),
                            ),
                            child: _paneView(tab, tab.panes[y * columns + x]),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Border? _splitBorder(DesktopTerminalTab tab, int index) {
    if (tab.panes.length == 1) return null;
    final divider = BorderSide(color: context.colors.success);
    if (tab.panes.length == 2) {
      if (index == 0) return null;
      return tab.horizontal ? Border(left: divider) : Border(top: divider);
    }
    final normal = BorderSide(color: context.colors.border);
    if (tab.activePane != tab.panes[index]) {
      return Border.fromBorderSide(normal);
    }
    return Border(
      top: index >= 2 ? divider : normal,
      bottom: index < 2 ? divider : normal,
      left: index.isOdd ? divider : normal,
      right: index.isEven ? divider : normal,
    );
  }

  Widget _resizeHandle({
    required bool vertical,
    required ValueChanged<double> onDrag,
    required VoidCallback onEnd,
  }) => TerminalResizeHandle(vertical: vertical, onDrag: onDrag, onEnd: onEnd);
  Widget _auxiliarySftp(
    DesktopTerminalWorkspace manager,
    DesktopTerminalTab active,
  ) {
    final visible = _sftp && !_grid;
    if (visible) _sftpMounted.add(active.server.id);
    final hosts = {
      for (final tab in manager.tabs)
        if (_sftpMounted.contains(tab.server.id)) tab.server.id: tab.server,
    };
    if (hosts.isEmpty) return const SizedBox.shrink();
    return Offstage(
      offstage: !visible,
      child: Row(
        children: [
          _resizeHandle(
            vertical: true,
            onDrag: (delta) => setState(
              () => _sftpWidth = (_visibleSideWidth - delta).clamp(320, 900),
            ),
            onEnd: () => _preference('sftpWidth', _sftpWidth),
          ),
          SizedBox(
            width: _visibleSideWidth,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: math.max(
                      0,
                      hosts.keys.toList().indexOf(active.server.id),
                    ),
                    children: [
                      for (final server in hosts.values)
                        ExcludeFocus(
                          key: ValueKey('sftp-host-${server.id}'),
                          excluding: !visible || active.server.id != server.id,
                          child: TickerMode(
                            enabled: visible && active.server.id == server.id,
                            child: DesktopSftpPanel(
                              key: ValueKey('sftp-${server.id}'),
                              server: server,
                              pathRequest: _sftpPaths.putIfAbsent(
                                server.id,
                                () => ValueNotifier<String?>(null),
                              ),
                              manager: manager.resources.sftpForHost(server.id),
                              onExecCommand: (command) => manager.input(
                                (manager.activeTab?.server.id == server.id
                                        ? manager.activeTab!
                                        : manager.tabs.firstWhere(
                                            (tab) => tab.server.id == server.id,
                                          ))
                                    .activePane,
                                '$command\n',
                                synchronize: false,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _auxiliaryAi(
    DesktopTerminalWorkspace manager,
    DesktopTerminalTab active,
  ) {
    if (_ai) active.activePane.aiMounted = true;
    final panes = manager.panes.where((p) => p.aiMounted).toList();
    if (panes.isEmpty) return const SizedBox.shrink();
    return Offstage(
      offstage: !_ai,
      child: Row(
        children: [
          _resizeHandle(
            vertical: true,
            onDrag: (delta) => setState(
              () => _aiWidth = (_visibleSideWidth - delta).clamp(320, 900),
            ),
            onEnd: () => _preference('aiWidth', _aiWidth),
          ),
          SizedBox(
            width: _visibleSideWidth,
            child: IndexedStack(
              index: math.max(0, panes.indexOf(active.activePane)),
              children: [
                for (final pane in panes)
                  ExcludeFocus(
                    key: ValueKey('ai-pane-${pane.id}'),
                    excluding: !_ai || pane != active.activePane,
                    child: TickerMode(
                      enabled: _ai && pane == active.activePane,
                      child: DesktopTerminalAgent(
                        key: ValueKey('ai-${pane.id}'),
                        pane: pane,
                        workspace: manager,
                        onClose: () => setState(() => _ai = false),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recent() {
    final hosts = ref.watch(desktopServerCatalogProvider);
    return hosts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(desktopServerCatalogProvider),
          child: Text('${dt(context, 'retry')}: $error'),
        ),
      ),
      data: (catalog) {
        final recent =
            catalog.hosts
                .where((s) => s.lastConnectTime != null && !s.isWindows)
                .toList()
              ..sort(
                (a, b) => b.lastConnectTime!.compareTo(a.lastConnectTime!),
              );
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dt(context, 'recent'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ManagementTable(
                  empty: dt(context, 'noRecent'),
                  columns: [
                    ManagementColumn(dt(context, 'name'), width: 180),
                    ManagementColumn(dt(context, 'sshCommand'), width: 320),
                    ManagementColumn(dt(context, 'lastConnected'), width: 180),
                    ManagementColumn.actions(dt(context, 'action'), width: 120),
                  ],
                  rows: [
                    for (final server in recent)
                      [
                        Text(
                          server.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SelectableText(
                          'ssh ${server.username}@${server.host} -p ${server.port}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          DateFormat(
                            'yyyy-MM-dd HH:mm:ss',
                          ).format(server.lastConnectTime!.toLocal()),
                        ),
                        ManagementLink(
                          label: dt(
                            context,
                            server.canConnect ? 'connect' : 'configure',
                          ),
                          onPressed: () => _connect(server),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TerminalHostPicker extends ConsumerWidget {
  const _TerminalHostPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped =
        ref.watch(desktopTerminalPreferencesProvider)['hostGroupCascader'] ==
        true;
    return ref
        .watch(desktopServerCatalogProvider)
        .when(
          loading: () => const SizedBox(
            width: 180,
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, stack) => TextButton(
            onPressed: () => ref.invalidate(desktopServerCatalogProvider),
            child: Text(dt(context, 'retry')),
          ),
          data: (catalog) {
            final hosts = orderTerminalItems(
              catalog.hosts,
              grouped
                  ? catalog.order.sections.expand((s) => s.itemIds)
                  : catalog.order.flatItemIds,
              (host) => host.id,
            ).where((host) => !host.isWindows).toList();
            TerminalCatalogEntry<List<ServerModel>> entry(ServerModel server) =>
                TerminalCatalogEntry(
                  id: server.id,
                  label: grouped
                      ? server.displayName
                      : '${server.displayName} ${server.host}',
                  value: [server],
                );
            if (hosts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text(dt(context, 'noHosts')),
              );
            }
            return TerminalCatalogMenu<List<ServerModel>>(
              onSelected: (servers) => Navigator.pop(context, servers),
              entries: [
                if (!grouped) ...hosts.map(entry),
                if (grouped)
                  for (final group in orderTerminalItems(
                    catalog.groups,
                    catalog.order.sections.map((s) => s.groupId),
                    (g) => g.id,
                  ))
                    if (hosts.any((host) => host.group == group.id))
                      TerminalCatalogEntry(
                        id: 'group-${group.id}',
                        label: group.displayName,
                        children: [
                          if (hosts
                                  .where((host) => host.group == group.id)
                                  .length >
                              1)
                            TerminalCatalogEntry(
                              id: 'all-${group.id}',
                              label: dt(context, 'connectAll'),
                              value: hosts
                                  .where(
                                    (host) =>
                                        host.group == group.id &&
                                        host.canConnect,
                                  )
                                  .toList(),
                            ),
                          ...hosts
                              .where((host) => host.group == group.id)
                              .map(entry),
                        ],
                      ),
              ],
            );
          },
        );
  }
}

class _TerminalScriptPicker extends ConsumerWidget {
  const _TerminalScriptPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped =
        ref.watch(
          desktopTerminalPreferencesProvider,
        )['scriptLibraryCascader'] ==
        true;
    return ref
        .watch(desktopTerminalScriptCatalogProvider)
        .when(
          loading: () => const SizedBox(
            width: 180,
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, stack) => TextButton(
            onPressed: () =>
                ref.invalidate(desktopTerminalScriptCatalogProvider),
            child: Text(dt(context, 'retry')),
          ),
          data: (catalog) {
            TerminalCatalogEntry<(String, bool)> entry(ScriptModel script) =>
                TerminalCatalogEntry(
                  id: script.id,
                  label: script.name,
                  value: (script.command, script.useBase64),
                );
            if (catalog.scripts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text(dt(context, 'noScripts')),
              );
            }
            return TerminalCatalogMenu<(String, bool)>(
              onSelected: (script) => Navigator.pop(context, script),
              entries: [
                if (!grouped) ...catalog.scripts.map(entry),
                if (grouped)
                  for (final group in catalog.groups)
                    if (catalog.scripts.any(
                      (script) => script.group == group.id,
                    ))
                      TerminalCatalogEntry(
                        id: 'group-${group.id}',
                        label: group.name,
                        children: catalog.scripts
                            .where((script) => script.group == group.id)
                            .map(entry)
                            .toList(),
                      ),
              ],
            );
          },
        );
  }
}
