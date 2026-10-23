import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/plus_info_notifier.dart';
import '../servers/server_model.dart';
import '../shell/sftp_session_manager.dart';
import '../terminal/desktop/desktop_sftp_panel.dart';
import '../terminal/desktop/terminal_widgets.dart';
import 'file_transfer_client.dart';
import 'desktop_transfer_tasks.dart';

/// Each browser owns a manager: selecting or reconnecting one side never changes
/// the other browser or a terminal's SFTP session, even for the same host.
class DesktopFileTransferPage extends ConsumerStatefulWidget {
  const DesktopFileTransferPage({
    super.key,
    this.managerFactory = SftpSessionManager.new,
  });
  final SftpSessionManager Function() managerFactory;
  @override
  ConsumerState<DesktopFileTransferPage> createState() =>
      _DesktopFileTransferPageState();
}

class _DesktopFileTransferPageState
    extends ConsumerState<DesktopFileTransferPage> {
  late final SftpSessionManager _left, _right;
  ServerModel? _leftHost, _rightHost;
  bool _optionsVisible = false;
  final _options = {'delete': false, 'partial': true, 'compress': true};
  late final FileTransferClient _client;
  int _completed = 0;
  @override
  void initState() {
    super.initState();
    _left = widget.managerFactory();
    _right = widget.managerFactory();
    _client = ref.read(fileTransferClientProvider)..addListener(_changed);
    unawaited(_client.connect());
  }

  void _changed() {
    if (_completed == _client.completedRevision) return;
    _completed = _client.completedRevision;
    for (final manager in [_left, _right]) {
      if (manager.activeSession?.isConnected == true) {
        unawaited(manager.refreshActive().catchError((Object _) {}));
      }
    }
  }

  @override
  void dispose() {
    _client.removeListener(_changed);
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  Future<void> _choose(bool left, ServerModel? server) async {
    final manager = left ? _left : _right;
    // Remove the old panel before disposing the state it listens to.
    setState(() {
      if (left) {
        _leftHost = null;
      } else {
        _rightHost = null;
      }
    });
    await WidgetsBinding.instance.endOfFrame;
    await manager.disconnectAll();
    if (!mounted) return;
    setState(() {
      if (left) {
        _leftHost = server;
      } else {
        _rightHost = server;
      }
    });
  }

  bool get _ready =>
      _client.connected &&
      !_client.submitting &&
      _left.activeSession?.isConnected == true &&
      _right.activeSession?.isConnected == true;

  Future<void> _transfer(bool toRight) async {
    final source = toRight ? _left : _right;
    final target = toRight ? _right : _left;
    final from = source.activeSession!, to = target.activeSession!;
    final entries = from.entries
        .where((e) => from.selectedNames.contains(e.name))
        .toList();
    if (entries.isEmpty) {
      managementNotice(
        context,
        mx(context, '请先选择要传输的文件或文件夹', 'Select files or folders first'),
      );
      return;
    }
    final config = {
      'sourceHostId': from.server.id,
      'targetHostId': to.server.id,
      'sourcePaths': [
        for (final e in entries)
          {
            'path': path.posix.join(from.currentPath, e.name),
            'type': e.type,
            'size': e.size ?? 0,
          },
      ],
      'targetPath': to.currentPath,
      'method': 'rsync',
      'options': Map.of(_options),
    };
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => DesktopManagementDialog(
        width: 640,
        title: mx(context, '传输预览', 'Transfer preview'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${from.server.displayName} → ${to.server.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 14),
            Text(mx(context, '源文件 / 文件夹', 'Source files / folders')),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  path.posix.join(from.currentPath, e.name),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 12),
            Text(mx(context, '目标路径', 'Destination path')),
            const SizedBox(height: 8),
            SelectableText(to.currentPath),
            const SizedBox(height: 16),
            Text(
              mx(
                context,
                'Rsync · 同名文件将被覆盖。',
                'Rsync · Existing files with the same name will be overwritten.',
              ),
              style: TextStyle(color: context.colors.warning, fontSize: 13),
            ),
            if (_options['delete'] == true)
              Text(
                mx(
                  context,
                  '已启用：删除目标多余文件。',
                  'Enabled: delete extra destination files.',
                ),
                style: TextStyle(color: context.colors.danger, fontSize: 13),
              ),
          ],
        ),
        actions: [
          ManagementButton(
            label: mx(context, '取消', 'Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ManagementButton(
            label: mx(context, '开始传输', 'Start transfer'),
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && _client.connected) {
      _client.start(config);
      _showTasks();
    }
  }

  void _showTasks() {
    _client.refresh();
    unawaited(
      showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DesktopTransferTasks(client: _client),
      ),
    );
  }

  Widget _panel(bool left, List<ServerModel> hosts, bool plus) {
    final server = left ? _leftHost : _rightHost;
    final manager = left ? _left : _right;
    final status =
        manager.activeSession?.status ?? SftpConnectionStatus.disconnected;
    final (statusLabel, statusColor) = switch (status) {
      SftpConnectionStatus.connected => (
        mx(context, '已连接', 'Connected'),
        context.colors.success,
      ),
      SftpConnectionStatus.connecting => (
        mx(context, '连接中', 'Connecting'),
        context.colors.warning,
      ),
      SftpConnectionStatus.error => (
        mx(context, '连接断开', 'Disconnected'),
        context.colors.danger,
      ),
      _ => (mx(context, '未连接', 'Not connected'), context.colors.muted),
    };
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.canvas,
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final selector = DesktopSelect(
                  key: ValueKey(
                    left ? 'transfer-left-host' : 'transfer-right-host',
                  ),
                  controlHeight: 32,
                  enabled: plus,
                  clearable: true,
                  options: {for (final h in hosts) h.id: h.displayName},
                  descriptions: {for (final h in hosts) h.id: h.host},
                  values: server == null ? [] : [server.id],
                  placeholder: mx(context, '选择服务器', 'Select server'),
                  onSelected: (id) => _choose(
                    left,
                    id.isEmpty ? null : hosts.firstWhere((h) => h.id == id),
                  ),
                );
                final badge = ManagementTag(statusLabel, color: statusColor);
                // Keep the selector usable when two panes share the minimum window.
                if (constraints.maxWidth < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      selector,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: badge),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: selector),
                    const SizedBox(width: 12),
                    badge,
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: server == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TerminalIcon(
                          Icons.desktop_windows_outlined,
                          size: 48,
                          color: context.colors.softMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          mx(context, '请选择一台服务器', 'Select a server'),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : DesktopSftpPanel(
                    key: ValueKey('${left ? 'left' : 'right'}-${server.id}'),
                    server: server,
                    manager: manager,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fileTransferClientProvider);
    final catalog = ref.watch(desktopServerCatalogProvider);
    final hosts =
        catalog.valueOrNull?.hosts
            .where((h) => h.canConnect && !h.isWindows)
            .toList() ??
        [];
    final plus = ref.watch(isPlusActiveProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([_left, _right, _client]),
      builder: (context, _) => AnimatedBuilder(
        animation: Listenable.merge([..._left.sessions, ..._right.sessions]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.canvas,
                border: Border(
                  bottom: BorderSide(color: context.colors.border),
                ),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.success.withValues(alpha: .1),
                      border: Border.all(
                        color: context.colors.success.withValues(alpha: .2),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      mx(
                        context,
                        '传输前需在服务器上安装 sshpass、rsync',
                        'Install sshpass and rsync on servers before transferring',
                      ),
                      style: TextStyle(
                        color: context.colors.success,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ManagementButton(
                        label: mx(context, '任务管理', 'Tasks'),
                        primary: true,
                        height: 32,
                        leading: const TerminalIcon(Icons.format_list_bulleted),
                        trailing: _client.runningCount == 0
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: context.colors.danger,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_client.runningCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                        onPressed: _showTasks,
                      ),
                      ManagementButton(
                        label: mx(context, '传输选项', 'Transfer options'),
                        height: 32,
                        leading: const TerminalIcon(Icons.settings_outlined),
                        onPressed: () =>
                            setState(() => _optionsVisible = !_optionsVisible),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (catalog.hasError)
              ManagementError(
                message: managementError(catalog.error!),
                onRetry: () => ref.invalidate(desktopServerCatalogProvider),
              ),
            if (_client.error != null)
              ManagementError(
                message: _client.error!,
                onRetry: _client.connected ? _client.refresh : _client.connect,
              ),
            if (!plus)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  mx(
                    context,
                    '文件对传为 Plus 功能，请在系统设置中激活。',
                    'File transfer requires Plus. Activate it in Settings.',
                  ),
                  style: TextStyle(color: context.colors.warning, fontSize: 13),
                ),
              ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: !_optionsVisible
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.canvas,
                        border: Border(
                          bottom: BorderSide(color: context.colors.border),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            mx(context, '传输选项', 'Transfer options'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.colors.text,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              for (final entry in _options.entries)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: entry.value,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (v) => setState(
                                        () => _options[entry.key] = v == true,
                                      ),
                                    ),
                                    Text(switch (entry.key) {
                                      'delete' => mx(
                                        context,
                                        '删除目标多余文件 (--delete)',
                                        'Delete extra destination files (--delete)',
                                      ),
                                      'partial' => mx(
                                        context,
                                        '支持断点续传 (--partial)',
                                        'Resume partial transfers (--partial)',
                                      ),
                                      _ => mx(
                                        context,
                                        '启用压缩传输 (-z)',
                                        'Compress transfers (-z)',
                                      ),
                                    }, style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: _panel(true, hosts, plus)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ManagementButton(
                            key: const Key('transfer-to-right'),
                            label: mx(context, '传输', 'Send'),
                            height: 40,
                            trailing: const TerminalIcon(Icons.arrow_forward),
                            primary: true,
                            onPressed:
                                _ready &&
                                    plus &&
                                    _left
                                        .activeSession!
                                        .selectedNames
                                        .isNotEmpty
                                ? () => _transfer(true)
                                : null,
                          ),
                          const SizedBox(height: 12),
                          ManagementButton(
                            key: const Key('transfer-to-left'),
                            label: mx(context, '传输', 'Send'),
                            height: 40,
                            leading: const TerminalIcon(Icons.arrow_back),
                            primary: true,
                            onPressed:
                                _ready &&
                                    plus &&
                                    _right
                                        .activeSession!
                                        .selectedNames
                                        .isNotEmpty
                                ? () => _transfer(false)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _panel(false, hosts, plus)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
