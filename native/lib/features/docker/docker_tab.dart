import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../state/auth_notifier.dart';
import '../../state/docker_providers.dart';
import '../../state/host_list_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/storage_providers.dart';
import '../servers/server_model.dart';
import '../shell/tab_header.dart';
import 'docker_container.dart';
import 'docker_icon.dart';
import 'docker_session_manager.dart';

class DockerTab extends StatelessWidget {
  const DockerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: const DockerPanel(showHeader: true),
    );
  }
}

class DockerPanel extends ConsumerStatefulWidget {
  const DockerPanel({
    super.key,
    this.showHeader = false,
    this.initialHostId,
    this.lockToHost = false,
    this.allowDisconnect = true,
  });

  final bool showHeader;
  final String? initialHostId;
  final bool lockToHost;
  final bool allowDisconnect;

  @override
  ConsumerState<DockerPanel> createState() => _DockerPanelState();
}

class _DockerPanelState extends ConsumerState<DockerPanel> {
  bool _connecting = false;
  String? _autoConnectAttemptedHostId;

  Future<void> _refreshHosts() => runRefreshWithFeedback(
    context,
    () => ref.read(hostListProvider.notifier).refresh(throwOnError: true),
  );

  Future<void> _openServerPicker() async {
    final manager = ref.read(dockerSessionManagerProvider);
    final selected = await showModalBottomSheet<ServerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => _DockerServerPickerSheet(
        connectedServerIds: manager.sessions
            .where(
              (session) => session.status == DockerConnectionStatus.connected,
            )
            .map((session) => session.server.id)
            .toSet(),
        activeServerId: manager.activeHostId,
        onRefresh: _refreshHosts,
      ),
    );
    if (selected == null || !mounted) return;
    await _connectOrActivate(selected);
  }

  Future<void> _connectOrActivate(ServerModel server) async {
    final l = AppLocalizations.of(context);
    final manager = ref.read(dockerSessionManagerProvider);
    if (manager.isConnected(server.id)) {
      manager.activate(server.id);
      return;
    }
    if (server.isWindows) {
      _showSnack(l.tr('servers.windowsUnsupported'));
      return;
    }
    if (!server.canConnect) {
      _showSnack(l.tr('servers.notConfigured'));
      return;
    }
    if (!ref.read(isPlusActiveProvider)) {
      _showSnack(l.tr('docker.plusRequired'));
      return;
    }
    final authSession = ref.read(authProvider).session;
    if (authSession == null) return;

    setState(() => _connecting = true);
    try {
      await manager.connect(
        server: server,
        authSession: authSession,
        cookieStore: ref.read(cookieStoreProvider),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hostsAsync = ref.watch(hostListProvider);
    final manager = ref.watch(dockerSessionManagerProvider);
    final isPlusActive = ref.watch(isPlusActiveProvider);

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final session = manager.activeSession;
        final showSelector =
            !widget.lockToHost &&
            !_connecting &&
            session != null &&
            session.status != DockerConnectionStatus.connecting;
        return Column(
          children: [
            if (widget.showHeader)
              TabHeader(
                title: l.tr('tabs.docker'),
                actions: showSelector
                    ? [
                        _DockerHeaderSelector(
                          session: session,
                          onTap: _openServerPicker,
                          onDisconnect: widget.allowDisconnect
                              ? () => manager.disconnectActive()
                              : null,
                        ),
                      ]
                    : const [],
              ),
            Expanded(
              child: RefreshIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.card,
                onRefresh: () async {
                  if (manager.activeSession == null) {
                    await _refreshHosts();
                  } else {
                    manager.reconnectActive();
                  }
                },
                child: hostsAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(
                      color: context.colors.primary,
                    ),
                  ),
                  error: (error, _) {
                    if (error is UnauthorizedFailure) {
                      return const SizedBox.shrink();
                    }
                    return _DockerMessageList(
                      message: error.toString(),
                      action: TextButton(
                        onPressed: _refreshHosts,
                        child: Text(l.tr('common.retry')),
                      ),
                    );
                  },
                  data: (servers) {
                    _autoConnectInitialServer(servers);
                    if (!isPlusActive) {
                      return _DockerMessageList(
                        message: l.tr('docker.plusRequired'),
                        icon: Icons.workspace_premium_outlined,
                      );
                    }
                    if (_connecting ||
                        session?.status == DockerConnectionStatus.connecting) {
                      return _DockerConnectingView(
                        server: session?.server,
                        onCancel: session != null
                            ? () => manager.disconnectActive()
                            : null,
                      );
                    }
                    if (session == null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 72, 16, 110),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.58,
                            child: Center(
                              child: _DockerEmptyCard(
                                onChooseServer: _openServerPicker,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return _DockerContainerList(
                      session: session,
                      manager: manager,
                      onRefresh: manager.reconnectActive,
                      onOpenPort: _openPort,
                      onShowLogs: _showLogs,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _autoConnectInitialServer(List<ServerModel> servers) {
    final hostId = widget.initialHostId;
    if (hostId == null || _autoConnectAttemptedHostId == hostId) return;
    final server = servers.where((item) => item.id == hostId).firstOrNull;
    if (server == null) return;
    _autoConnectAttemptedHostId = hostId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connectOrActivate(server);
    });
  }

  Future<void> _openPort(ServerModel server, String port) async {
    final match = RegExp(r':(\d+)->').firstMatch(port);
    if (match == null) {
      _showSnack(AppLocalizations.of(context).tr('docker.openPortFailed'));
      return;
    }
    final url = Uri.parse('http://${server.host}:${match.group(1)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _showLogs(DockerContainer container) async {
    final manager = ref.read(dockerSessionManagerProvider);
    manager.getLogs(container);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => _DockerLogsSheet(container: container),
    );
  }
}

class _DockerContainerList extends StatefulWidget {
  const _DockerContainerList({
    required this.session,
    required this.manager,
    required this.onRefresh,
    required this.onOpenPort,
    required this.onShowLogs,
  });

  final DockerSessionState session;
  final DockerSessionManager manager;
  final VoidCallback onRefresh;
  final Future<void> Function(ServerModel server, String port) onOpenPort;
  final Future<void> Function(DockerContainer container) onShowLogs;

  @override
  State<_DockerContainerList> createState() => _DockerContainerListState();
}

class _DockerContainerListState extends State<_DockerContainerList> {
  final Set<String> _selected = {};
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _autoRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 3500),
      (_) {
        if (_selected.isNotEmpty) return;
        final s = widget.session;
        if (s.loading || s.status != DockerConnectionStatus.connected) return;
        s.client.refresh();
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  bool get _allSelected =>
      widget.session.containers.isNotEmpty &&
      _selected.length == widget.session.containers.length;

  bool get _hasSelection => _selected.isNotEmpty;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.session.containers.map((c) => c.id));
      }
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  List<DockerContainer> get _selectedContainers => widget.session.containers
      .where((c) => _selected.contains(c.id))
      .toList(growable: false);

  void _batchStart() {
    for (final c in _selectedContainers) {
      if (!c.isRunning) widget.manager.start(c);
    }
  }

  void _batchRestart() {
    for (final c in _selectedContainers) {
      if (c.isRunning) widget.manager.restart(c);
    }
  }

  void _batchStop() {
    for (final c in _selectedContainers) {
      if (c.isRunning) widget.manager.stop(c);
    }
  }

  Future<void> _batchDelete() async {
    final count = _selected.length;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.trf('docker.batchDeleteTitle', ['$count'])),
        content: Text(l.trf('docker.batchDeleteBody', ['$count'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('docker.batchDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final c in _selectedContainers) {
      widget.manager.delete(c);
    }
    setState(() => _selected.clear());
  }

  @override
  void didUpdateWidget(covariant _DockerContainerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.session.containers.map((c) => c.id).toSet();
    _selected.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = widget.session;
    if (session.status == DockerConnectionStatus.error) {
      final message = session.errorMessage == 'docker_not_plus'
          ? l.tr('docker.notPlus')
          : session.errorMessage == 'docker_connect_fail'
          ? l.tr('docker.connectFailed')
          : session.errorMessage ?? l.tr('docker.connectFailed');
      return _DockerMessageList(
        message: message,
        icon: Icons.error_outline_rounded,
        action: TextButton(
          onPressed: widget.onRefresh,
          child: Text(l.tr('common.retry')),
        ),
      );
    }
    if (session.loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (session.containers.isEmpty) {
      return _DockerMessageList(
        message: l.tr('docker.noContainers'),
        icon: Icons.inventory_2_outlined,
        action: TextButton.icon(
          onPressed: widget.onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(l.tr('docker.refresh')),
        ),
      );
    }
    return Column(
      children: [
        _DockerToolbar(
          allSelected: _allSelected,
          indeterminate: _hasSelection && !_allSelected,
          selectedCount: _selected.length,
          refreshing: session.refreshing,
          operating: session.operatingIds.isNotEmpty,
          onToggleAll: _toggleAll,
          onRefresh: widget.onRefresh,
          onBatchStart: _hasSelection ? _batchStart : null,
          onBatchRestart: _hasSelection ? _batchRestart : null,
          onBatchStop: _hasSelection ? _batchStop : null,
          onBatchDelete: _hasSelection ? _batchDelete : null,
        ),
        Expanded(
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            itemBuilder: (context, index) {
              final container = session.containers[index];
              return _DockerContainerCard(
                server: session.server,
                container: container,
                operating: session.operatingIds.contains(container.id),
                selected: _selected.contains(container.id),
                onSelect: () => _toggle(container.id),
                onStart: () => widget.manager.start(container),
                onStop: () => widget.manager.stop(container),
                onRestart: () => widget.manager.restart(container),
                onDelete: () => _confirmDelete(context, container),
                onLogs: () => widget.onShowLogs(container),
                onOpenPort: (port) =>
                    widget.onOpenPort(session.server, port),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemCount: session.containers.length,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DockerContainer container,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('docker.deleteTitle')),
        content: Text(l.trf('docker.deleteBody', [container.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('docker.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.manager.delete(container);
  }
}

class _DockerToolbar extends StatelessWidget {
  const _DockerToolbar({
    required this.allSelected,
    required this.indeterminate,
    required this.selectedCount,
    required this.refreshing,
    required this.operating,
    required this.onToggleAll,
    required this.onRefresh,
    required this.onBatchStart,
    required this.onBatchRestart,
    required this.onBatchStop,
    required this.onBatchDelete,
  });

  final bool allSelected;
  final bool indeterminate;
  final int selectedCount;
  final bool refreshing;
  final bool operating;
  final VoidCallback onToggleAll;
  final VoidCallback onRefresh;
  final VoidCallback? onBatchStart;
  final VoidCallback? onBatchRestart;
  final VoidCallback? onBatchStop;
  final VoidCallback? onBatchDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: allSelected ? true : (indeterminate ? null : false),
              tristate: true,
              onChanged: (_) => onToggleAll(),
              activeColor: c.primary,
              side: BorderSide(color: c.strongBorder, width: 1.8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onToggleAll,
            child: Text(
              selectedCount > 0
                  ? l.trf('docker.selectedCount', ['$selectedCount'])
                  : l.tr('docker.selectAll'),
              style: TextStyle(
                color: selectedCount > 0 ? c.primary : c.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          if (selectedCount > 0) ...[
            if (operating)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                ),
              ),
            _DockerBatchButton(
              icon: Icons.play_arrow_rounded,
              color: c.success,
              tooltip: l.tr('docker.batchStart'),
              onTap: operating ? null : onBatchStart,
            ),
            const SizedBox(width: 4),
            _DockerBatchButton(
              icon: Icons.restart_alt_rounded,
              color: c.primary,
              tooltip: l.tr('docker.batchRestart'),
              onTap: operating ? null : onBatchRestart,
            ),
            const SizedBox(width: 4),
            _DockerBatchButton(
              icon: Icons.pause_rounded,
              color: c.warning,
              tooltip: l.tr('docker.batchStop'),
              onTap: operating ? null : onBatchStop,
            ),
            const SizedBox(width: 4),
            _DockerBatchButton(
              icon: Icons.delete_outline_rounded,
              color: c.danger,
              tooltip: l.tr('docker.batchDelete'),
              onTap: operating ? null : onBatchDelete,
            ),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              onPressed: refreshing ? null : onRefresh,
              padding: EdgeInsets.zero,
              tooltip: l.tr('docker.refresh'),
              icon: refreshing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.primary,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, size: 22, color: c.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockerBatchButton extends StatelessWidget {
  const _DockerBatchButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _DockerContainerCard extends StatelessWidget {
  const _DockerContainerCard({
    required this.server,
    required this.container,
    required this.operating,
    required this.selected,
    required this.onSelect,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onDelete,
    required this.onLogs,
    required this.onOpenPort,
  });

  final ServerModel server;
  final DockerContainer container;
  final bool operating;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onDelete;
  final VoidCallback onLogs;
  final ValueChanged<String> onOpenPort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? c.primary.withValues(alpha: 0.5) : c.border,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: c.primary.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          else
            BoxShadow(
              color: c.primary.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onSelect(),
                  activeColor: c.primary,
                  side: BorderSide(color: c.strongBorder, width: 1.8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.banner,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: IconTheme(
                  data: IconThemeData(color: c.primary, size: 24),
                  child: const DockerIcon(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      container.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      container.image,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.softMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _DockerStatusPill(status: container.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DockerInfoChip(label: 'ID', value: container.shortId),
              if (container.uptime.isNotEmpty)
                _DockerInfoChip(label: 'UP', value: container.uptime),
            ],
          ),
          if (container.ports.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final port in container.ports)
                  _DockerPortChip(
                    port: port,
                    mapped: port.contains('->'),
                    onTap: port.contains('->') ? () => onOpenPort(port) : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _DockerCircleAction(
                tooltip: l.tr('docker.start'),
                icon: Icons.play_arrow_rounded,
                color: c.success,
                enabled: !container.isRunning && !operating,
                onTap: onStart,
              ),
              const SizedBox(width: 10),
              _DockerCircleAction(
                tooltip: l.tr('docker.restart'),
                icon: Icons.restart_alt_rounded,
                color: c.primary,
                enabled: container.isRunning && !operating,
                onTap: onRestart,
              ),
              const SizedBox(width: 10),
              _DockerCircleAction(
                tooltip: l.tr('docker.stop'),
                icon: Icons.pause_rounded,
                color: c.warning,
                enabled: container.isRunning && !operating,
                onTap: onStop,
              ),
              const SizedBox(width: 10),
              _DockerCircleAction(
                tooltip: l.tr('docker.delete'),
                icon: Icons.delete_outline_rounded,
                color: c.danger,
                enabled: !operating,
                onTap: onDelete,
              ),
              const SizedBox(width: 10),
              _DockerCircleAction(
                tooltip: l.tr('docker.logs'),
                icon: Icons.article_outlined,
                color: c.muted,
                enabled: !operating,
                onTap: onLogs,
              ),
              if (operating) ...[
                const Spacer(),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DockerHeaderSelector extends StatelessWidget {
  const _DockerHeaderSelector({
    required this.session,
    required this.onTap,
    required this.onDisconnect,
  });

  final DockerSessionState session;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isError = session.status == DockerConnectionStatus.error;
    final dotColor = isError ? c.danger : c.success;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: screenWidth / 4,
        maxWidth: screenWidth / 2,
      ),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: c.strongBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.server.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: c.muted,
                  ),
                  if (onDisconnect != null)
                    InkResponse(
                      radius: 14,
                      onTap: onDisconnect,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockerEmptyCard extends StatelessWidget {
  const _DockerEmptyCard({required this.onChooseServer});

  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420, minHeight: 348),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _DockerOrbitIcon(),
          const SizedBox(height: 18),
          SizedBox(
            height: 24,
            child: Text(
              l.tr('docker.emptyTitle'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Text(
              l.tr('docker.emptyBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.softMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _DockerPrimaryButton(
            icon: const DockerIcon(size: 16),
            label: l.tr('docker.chooseServer'),
            trailing: Icons.keyboard_arrow_down_rounded,
            onTap: onChooseServer,
          ),
        ],
      ),
    );
  }
}

class _DockerOrbitIcon extends StatelessWidget {
  const _DockerOrbitIcon();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 14,
            child: _DockerDot(size: 10, color: c.banner),
          ),
          Positioned(
            right: 12,
            top: 8,
            child: _DockerDot(size: 8, color: c.accent),
          ),
          Positioned(
            right: 4,
            bottom: 12,
            child: _DockerDot(size: 12, color: c.banner),
          ),
          const Positioned(
            left: 0,
            bottom: 24,
            child: _DockerDot(size: 6, color: Color(0xFFEFD9A2)),
          ),
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: c.banner,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.accent.withValues(alpha: 0.4)),
              ),
              child: IconTheme(
                data: IconThemeData(color: c.primary, size: 42),
                child: const DockerIcon(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockerDot extends StatelessWidget {
  const _DockerDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DockerPrimaryButton extends StatelessWidget {
  const _DockerPrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final Widget icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(size: 16, color: c.fontOnPrimary),
                child: icon,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: c.fontOnPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, size: 16, color: c.fontOnPrimary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockerConnectingView extends StatelessWidget {
  const _DockerConnectingView({required this.server, this.onCancel});

  final ServerModel? server;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 96, 16, 110),
      children: [
        Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: c.primary),
              const SizedBox(height: 16),
              Text(
                l.tr('docker.connecting'),
                style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
              ),
              if (server != null) ...[
                const SizedBox(height: 6),
                Text(server!.displayName, style: TextStyle(color: c.softMuted)),
              ],
              if (onCancel != null) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(l.tr('common.cancel')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DockerMessageList extends StatelessWidget {
  const _DockerMessageList({required this.message, this.action, this.icon});

  final String message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 110),
      children: [
        if (icon != null) ...[
          Icon(icon, size: 44, color: c.softMuted),
          const SizedBox(height: 12),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
        ),
        if (action != null) ...[
          const SizedBox(height: 10),
          Center(child: action),
        ],
      ],
    );
  }
}

class _DockerStatusPill extends StatelessWidget {
  const _DockerStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (status) {
      'running' => c.success,
      'exited' => c.danger,
      'paused' => c.warning,
      _ => c.softMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Text(
        status.isEmpty ? '--' : status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DockerInfoChip extends StatelessWidget {
  const _DockerInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.border),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: c.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DockerPortChip extends StatelessWidget {
  const _DockerPortChip({required this.port, required this.mapped, this.onTap});

  final String port;
  final bool mapped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: mapped ? c.accentSoft : c.chip,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mapped) ...[
                Icon(Icons.open_in_new_rounded, size: 12, color: c.primary),
                const SizedBox(width: 4),
              ],
              Text(
                port,
                style: TextStyle(
                  color: mapped ? c.primary : c.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockerCircleAction extends StatelessWidget {
  const _DockerCircleAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = enabled ? color : c.softMuted;
    final border = enabled ? color.withValues(alpha: 0.36) : c.border;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

class _DockerLogsSheet extends ConsumerStatefulWidget {
  const _DockerLogsSheet({required this.container});

  final DockerContainer container;

  @override
  ConsumerState<_DockerLogsSheet> createState() => _DockerLogsSheetState();
}

class _DockerLogsSheetState extends ConsumerState<_DockerLogsSheet> {
  late final DockerSessionManager _manager;
  Timer? _autoRefreshTimer;
  ScrollController? _scrollController;
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    _manager = ref.read(dockerSessionManagerProvider);
    _manager.addListener(_onLogsChanged);
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_manager.activeSession?.status != DockerConnectionStatus.connected) {
        return;
      }
      _manager.refreshLogs(widget.container);
    });
  }

  @override
  void dispose() {
    _manager.removeListener(_onLogsChanged);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _onLogsChanged() {
    if (_initialScrollDone) return;
    final logs = _manager.activeSession?.logs ?? '';
    if (logs.trim().isEmpty) return;
    _initialScrollDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scrollController;
      if (!mounted || c == null || !c.hasClients) return;
      c.jumpTo(c.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.76,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          _scrollController = scrollController;
          return Container(
            decoration: BoxDecoration(
              color: c.canvas,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.strongBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.trf('docker.logsTitle', [widget.container.name]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _manager.getLogs(widget.container),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _manager,
                    builder: (context, _) {
                      final logs = _manager.activeSession?.logs ?? '';
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: SelectableText(
                            logs.trim().isEmpty
                                ? l.tr('docker.noLogs')
                                : logs,
                            style: const TextStyle(
                              color: Color(0xFFEDE7DB),
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DockerServerPickerSheet extends ConsumerStatefulWidget {
  const _DockerServerPickerSheet({
    required this.connectedServerIds,
    required this.activeServerId,
    required this.onRefresh,
  });

  final Set<String> connectedServerIds;
  final String? activeServerId;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_DockerServerPickerSheet> createState() =>
      _DockerServerPickerSheetState();
}

class _DockerServerPickerSheetState
    extends ConsumerState<_DockerServerPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostListProvider);
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.64,
        minChildSize: 0.38,
        maxChildSize: 0.86,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: c.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.strongBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('docker.sheetTitle'),
                            style: TextStyle(
                              color: c.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l.tr('docker.sheetSubtitle'),
                            style: TextStyle(
                              color: c.softMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchCtrl,
                    cursorColor: c.primary,
                    decoration: InputDecoration(
                      hintText: l.tr('docker.searchHint'),
                      prefixIcon: const Icon(Icons.search, size: 19),
                      isDense: true,
                      filled: true,
                      fillColor: c.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
              ),
              Expanded(
                child: hostsAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: c.primary),
                  ),
                  error: (error, _) => ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Text(error.toString(), textAlign: TextAlign.center),
                      Center(
                        child: TextButton(
                          onPressed: widget.onRefresh,
                          child: Text(l.tr('common.retry')),
                        ),
                      ),
                    ],
                  ),
                  data: (servers) => _buildServerList(
                    context,
                    scrollController,
                    _filterServers(servers),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerList(
    BuildContext context,
    ScrollController scrollController,
    List<ServerModel> servers,
  ) {
    final l = AppLocalizations.of(context);
    if (servers.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
        children: [
          Text(
            l.tr('servers.emptyFiltered'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted),
          ),
        ],
      );
    }
    final connected = servers
        .where((server) => widget.connectedServerIds.contains(server.id))
        .toList(growable: false);
    final disconnected = servers
        .where((server) => !widget.connectedServerIds.contains(server.id))
        .toList(growable: false);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (connected.isNotEmpty) ...[
          _DockerSectionLabel(l.tr('docker.connectedSection')),
          for (final server in connected)
            _DockerServerRow(
              server: server,
              connected: true,
              active: server.id == widget.activeServerId,
              onTap: () => Navigator.of(context).pop(server),
            ),
        ],
        if (disconnected.isNotEmpty) ...[
          _DockerSectionLabel(l.tr('docker.disconnectedSection')),
          for (final server in disconnected)
            _DockerServerRow(
              server: server,
              connected: false,
              active: false,
              onTap: () => Navigator.of(context).pop(server),
            ),
        ],
      ],
    );
  }

  List<ServerModel> _filterServers(List<ServerModel> servers) {
    final filtered = servers.where((server) => !server.isWindows).toList();
    if (_query.isEmpty) return filtered;
    return filtered
        .where((server) {
          final haystack = [
            server.displayName,
            server.host,
            server.username,
            ...server.tag,
          ].join(' ').toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }
}

class _DockerSectionLabel extends StatelessWidget {
  const _DockerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.softMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DockerServerRow extends StatelessWidget {
  const _DockerServerRow({
    required this.server,
    required this.connected,
    required this.active,
    required this.onTap,
  });

  final ServerModel server;
  final bool connected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? c.accentSoft : c.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.banner,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconTheme(
                    data: IconThemeData(color: c.primary, size: 20),
                    child: const DockerIcon(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        server.connectionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.softMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  connected
                      ? l.tr('docker.statusConnected')
                      : l.tr('docker.statusDisconnected'),
                  style: TextStyle(
                    color: connected ? c.success : c.softMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
