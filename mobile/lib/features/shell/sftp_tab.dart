import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../features/servers/server_model.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/terminal_providers.dart';
import 'sftp_session_manager.dart';

class SftpTab extends ConsumerStatefulWidget {
  const SftpTab({super.key});

  @override
  ConsumerState<SftpTab> createState() => _SftpTabState();
}

class _SftpTabState extends ConsumerState<SftpTab> {
  bool _connecting = false;

  Future<void> _refresh() => ref.read(hostListProvider.notifier).refresh();

  Future<void> _openServerPicker() async {
    final manager = ref.read(sftpSessionManagerProvider);
    final selected = await showModalBottomSheet<ServerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => _SftpServerPickerSheet(
        connectedServerIds: manager.sessions
            .where(
              (session) => session.status == SftpConnectionStatus.connected,
            )
            .map((session) => session.server.id)
            .toSet(),
        activeServerId: manager.activeHostId,
        onRefresh: _refresh,
      ),
    );
    if (selected == null || !mounted) return;
    await _connectOrActivate(selected);
  }

  Future<void> _connectOrActivate(ServerModel server) async {
    final l = AppLocalizations.of(context);
    final manager = ref.read(sftpSessionManagerProvider);
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

    setState(() => _connecting = true);
    try {
      final config = await ref
          .read(serverRepositoryProvider)
          .fetchSshConfig(server.id);
      await manager.connect(
        server: server,
        config: config,
        loadFavorites: (hostId) =>
            ref.read(serverRepositoryProvider).fetchSftpFavorites(hostId),
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
    final manager = ref.watch(sftpSessionManagerProvider);

    return Scaffold(
      backgroundColor: _SftpPalette.canvas,
      body: RefreshIndicator(
        color: _SftpPalette.primary,
        backgroundColor: _SftpPalette.card,
        onRefresh: _refresh,
        child: hostsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _SftpPalette.primary),
          ),
          error: (error, _) {
            if (error is UnauthorizedFailure) return const SizedBox.shrink();
            return _SftpMessageList(
              message: error.toString(),
              action: TextButton(
                onPressed: _refresh,
                child: Text(l.tr('common.retry')),
              ),
            );
          },
          data: (_) => AnimatedBuilder(
            animation: manager,
            builder: (context, _) {
              final session = manager.activeSession;
              if (_connecting ||
                  session?.status == SftpConnectionStatus.connecting) {
                return _SftpConnectingView(server: session?.server);
              }
              if (session == null) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.58,
                      child: Center(
                        child: _SftpEmptyCard(
                          onChooseServer: _openServerPicker,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return _SftpConnectedView(
                session: session,
                manager: manager,
                onChooseServer: _openServerPicker,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SftpConnectedView extends StatelessWidget {
  const _SftpConnectedView({
    required this.session,
    required this.manager,
    required this.onChooseServer,
  });

  final SftpSessionState session;
  final SftpSessionManager manager;
  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return Column(
          children: [
            _SftpTopSelector(
              session: session,
              onTap: onChooseServer,
              onDisconnect: () => manager.disconnectActive(),
            ),
            _SftpToolbar(session: session, manager: manager),
            _SftpPathBar(session: session, manager: manager),
            _SftpTableHeader(
              allSelected: session.allVisibleSelected,
              onSelectAll: session.toggleAllVisible,
            ),
            Expanded(
              child: Stack(
                children: [
                  if (session.entries.isEmpty && !session.loadingDirectory)
                    _SftpMessageList(
                      message: AppLocalizations.of(
                        context,
                      ).tr('sftp.emptyDirectory'),
                    )
                  else
                    ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: session.entries.length,
                      itemBuilder: (context, index) {
                        final entry = session.entries[index];
                        return _SftpFileRow(
                          entry: entry,
                          selected: session.selectedNames.contains(entry.name),
                          onTap: () {
                            if (session.hasSelection) {
                              session.toggleSelection(entry.name);
                            } else if (entry.isDirectory) {
                              manager.openPath(
                                manager.entryPath(session, entry),
                              );
                            }
                          },
                          onLongPress: () {
                            session.addSelection(entry.name);
                            _showFileActionSheet(context, session, entry);
                          },
                          onSelectionChanged: () =>
                              session.toggleSelection(entry.name),
                        );
                      },
                    ),
                  if (session.loadingDirectory)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x44F7EFE0),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _SftpPalette.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFileActionSheet(
    BuildContext context,
    SftpSessionState session,
    SftpFileEntry anchor,
  ) {
    final selectedEntries = session.entries
        .where((entry) => session.selectedNames.contains(entry.name))
        .toList(growable: false);
    final multi = selectedEntries.length > 1;
    final actions = <_SftpMenuAction>[
      const _SftpMenuAction(Icons.download_outlined, '下载'),
      const _SftpMenuAction(Icons.copy_outlined, '复制到...'),
      const _SftpMenuAction(Icons.drive_file_move_outline, '移动到...'),
      const _SftpMenuAction(Icons.archive_outlined, '压缩'),
      const _SftpMenuAction(Icons.delete_outline, '删除', destructive: true),
      if (!multi) const _SftpMenuAction(Icons.edit_outlined, '重命名'),
      if (!multi) const _SftpMenuAction(Icons.link_outlined, '复制文件路径'),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _SftpPalette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _SftpPalette.strongBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                ListTile(
                  dense: true,
                  leading: Icon(
                    action.icon,
                    color: action.destructive
                        ? _SftpPalette.danger
                        : _SftpPalette.muted,
                  ),
                  title: Text(
                    action.label,
                    style: TextStyle(
                      color: action.destructive
                          ? _SftpPalette.danger
                          : _SftpPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    if (action.label == '复制文件路径') {
                      Clipboard.setData(
                        ClipboardData(
                          text: SftpSessionManager.joinPath(
                            session.currentPath,
                            anchor.name,
                          ),
                        ),
                      );
                    }
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SftpMenuAction {
  const _SftpMenuAction(this.icon, this.label, {this.destructive = false});

  final IconData icon;
  final String label;
  final bool destructive;
}

class _SftpTopSelector extends StatelessWidget {
  const _SftpTopSelector({
    required this.session,
    required this.onTap,
    required this.onDisconnect,
  });

  final SftpSessionState session;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: _SftpPalette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _SftpPalette.strongBorder, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    size: 18,
                    color: _SftpPalette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.server.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _SftpPalette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _SftpPalette.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _SftpPalette.muted,
                  ),
                  const SizedBox(width: 6),
                  InkResponse(
                    radius: 18,
                    onTap: onDisconnect,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: _SftpPalette.muted,
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

class _SftpToolbar extends StatelessWidget {
  const _SftpToolbar({required this.session, required this.manager});

  final SftpSessionState session;
  final SftpSessionManager manager;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _SftpToolbarButton(
            label: l.tr('sftp.upload'),
            onTap: () => _showUploadMenu(context),
          ),
          const SizedBox(width: 8),
          _SftpToolbarButton(
            label: l.tr('sftp.newItem'),
            onTap: () => _showCreateMenu(context),
          ),
          const SizedBox(width: 8),
          _SftpToolbarButton(
            label: l.tr('sftp.favorites'),
            enabled: session.favorites.isNotEmpty,
            onTap: () => _showFavoritesMenu(context),
          ),
        ],
      ),
    );
  }

  void _showUploadMenu(BuildContext context) {
    _showOptionSheet(context, [
      _SftpSheetAction(Icons.upload_file_outlined, '上传文件', () {
        _showDeferredSnack(context);
      }),
      _SftpSheetAction(Icons.create_new_folder_outlined, '上传文件夹', () {
        _showDeferredSnack(context);
      }),
    ]);
  }

  void _showCreateMenu(BuildContext context) {
    _showOptionSheet(context, [
      _SftpSheetAction(Icons.insert_drive_file_outlined, '新建文件', () {
        _showNameDialog(context, type: 'file');
      }),
      _SftpSheetAction(Icons.create_new_folder_outlined, '新建文件夹', () {
        _showNameDialog(context, type: 'folder');
      }),
    ]);
  }

  void _showFavoritesMenu(BuildContext context) {
    _showOptionSheet(context, [
      for (final favorite in session.favorites)
        _SftpSheetAction(
          favorite.type == 'folder'
              ? Icons.folder_outlined
              : Icons.insert_drive_file_outlined,
          favorite.path,
          () {
            final target = favorite.type == 'folder'
                ? favorite.path
                : SftpSessionManager.parentPath(favorite.path);
            manager.openPath(target);
          },
        ),
    ]);
  }

  Future<void> _showNameDialog(
    BuildContext context, {
    required String type,
  }) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(type == 'folder' ? '新建文件夹' : '新建文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入名称'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      if (type == 'folder') {
        await manager.createDirectory(trimmed);
      } else {
        await manager.createFile(trimmed);
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showOptionSheet(BuildContext context, List<_SftpSheetAction> actions) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _SftpPalette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _SftpPalette.strongBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                ListTile(
                  dense: true,
                  leading: Icon(action.icon, color: _SftpPalette.muted),
                  title: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _SftpPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    action.onTap();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeferredSnack(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('上传文件/文件夹将在下一步接入系统选择器')));
  }
}

class _SftpToolbarButton extends StatelessWidget {
  const _SftpToolbarButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: enabled ? _SftpPalette.card : _SftpPalette.chip,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _SftpPalette.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? _SftpPalette.text : _SftpPalette.softMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: enabled ? _SftpPalette.muted : _SftpPalette.softMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SftpSheetAction {
  const _SftpSheetAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _SftpPathBar extends StatelessWidget {
  const _SftpPathBar({required this.session, required this.manager});

  final SftpSessionState session;
  final SftpSessionManager manager;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            _SftpIconAction(
              icon: Icons.chevron_left_rounded,
              onTap: manager.goParent,
            ),
            const SizedBox(width: 8),
            InkResponse(
              radius: 18,
              onTap: () => manager.openPath('/'),
              child: const Icon(
                Icons.home_outlined,
                size: 16,
                color: _SftpPalette.muted,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _SftpBreadcrumb(
                path: session.currentPath,
                manager: manager,
              ),
            ),
            _SftpIconAction(
              icon: Icons.refresh_rounded,
              onTap: manager.refreshActive,
            ),
            const SizedBox(width: 10),
            _SftpIconAction(
              icon: session.showHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onTap: () => manager.setShowHidden(!session.showHidden),
            ),
          ],
        ),
      ),
    );
  }
}

class _SftpBreadcrumb extends StatelessWidget {
  const _SftpBreadcrumb({required this.path, required this.manager});

  final String path;
  final SftpSessionManager manager;

  @override
  Widget build(BuildContext context) {
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => manager.openPath('/'),
          child: const Text(
            '/',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _SftpPalette.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: segments.length,
      separatorBuilder: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: _SftpPalette.softMuted,
          ),
        ),
      ),
      itemBuilder: (context, index) {
        final target = '/${segments.take(index + 1).join('/')}';
        return Center(
          child: InkWell(
            onTap: () => manager.openPath(target),
            child: Text(
              segments[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _SftpPalette.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SftpIconAction extends StatelessWidget {
  const _SftpIconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 20,
      onTap: onTap,
      child: Icon(icon, size: 18, color: _SftpPalette.muted),
    );
  }
}

class _SftpTableHeader extends StatelessWidget {
  const _SftpTableHeader({
    required this.allSelected,
    required this.onSelectAll,
  });

  final bool allSelected;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _SftpPalette.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Checkbox(
              value: allSelected,
              onChanged: (_) => onSelectAll(),
              activeColor: _SftpPalette.primary,
            ),
          ),
          const Expanded(
            child: Text(
              '名称',
              style: TextStyle(
                color: _SftpPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(
            width: 64,
            child: Text(
              '大小',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _SftpPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(
            width: 58,
            child: Text(
              '时间',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _SftpPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SftpFileRow extends StatelessWidget {
  const _SftpFileRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectionChanged,
  });

  final SftpFileEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _SftpPalette.banner : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 48,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _SftpPalette.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onSelectionChanged(),
                  activeColor: _SftpPalette.primary,
                ),
              ),
              Icon(
                entry.isDirectory
                    ? Icons.folder_rounded
                    : entry.isLink
                    ? Icons.link_rounded
                    : Icons.insert_drive_file_outlined,
                size: 20,
                color: entry.isDirectory
                    ? _SftpPalette.gold
                    : _SftpPalette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SftpPalette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  entry.isDirectory ? '-' : _formatSize(entry.size),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SftpPalette.softMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 58,
                child: Text(
                  _formatDate(entry.modifyTime),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SftpPalette.softMuted,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int? size) {
    if (size == null) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return unit == 0
        ? '${value.toInt()} ${units[unit]}'
        : '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    return '${local.month}/${local.day}';
  }
}

class _SftpConnectingView extends StatelessWidget {
  const _SftpConnectingView({required this.server});

  final ServerModel? server;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 24),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  color: _SftpPalette.primary,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l.tr('sftp.connecting'),
                style: const TextStyle(
                  color: _SftpPalette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                server?.displayName ?? '',
                style: const TextStyle(
                  color: _SftpPalette.softMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SftpEmptyCard extends StatelessWidget {
  const _SftpEmptyCard({required this.onChooseServer});

  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420, minHeight: 348),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _SftpOrbitIcon(),
          const SizedBox(height: 18),
          Text(
            l.tr('sftp.emptyTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _SftpPalette.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.tr('sftp.emptyBody'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _SftpPalette.softMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          _SftpPrimaryButton(
            icon: Icons.dns_outlined,
            label: l.tr('sftp.chooseServer'),
            trailing: Icons.keyboard_arrow_down_rounded,
            onTap: onChooseServer,
          ),
        ],
      ),
    );
  }
}

class _SftpOrbitIcon extends StatelessWidget {
  const _SftpOrbitIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          const Positioned(
            left: 6,
            top: 14,
            child: _SftpDot(size: 10, color: _SftpPalette.banner),
          ),
          const Positioned(
            right: 12,
            top: 8,
            child: _SftpDot(size: 8, color: _SftpPalette.gold),
          ),
          const Positioned(
            right: 4,
            bottom: 12,
            child: _SftpDot(size: 12, color: _SftpPalette.banner),
          ),
          const Positioned(
            left: 0,
            bottom: 24,
            child: _SftpDot(size: 6, color: Color(0xFFEFD9A2)),
          ),
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: _SftpPalette.banner,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x66E5B33A)),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: _SftpPalette.primary,
                size: 42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SftpDot extends StatelessWidget {
  const _SftpDot({required this.size, required this.color});

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

class _SftpPrimaryButton extends StatelessWidget {
  const _SftpPrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _SftpPalette.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: _SftpPalette.card),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _SftpPalette.card,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, size: 16, color: _SftpPalette.card),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SftpServerPickerSheet extends ConsumerStatefulWidget {
  const _SftpServerPickerSheet({
    required this.connectedServerIds,
    required this.activeServerId,
    required this.onRefresh,
  });

  final Set<String> connectedServerIds;
  final String? activeServerId;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_SftpServerPickerSheet> createState() =>
      _SftpServerPickerSheetState();
}

class _SftpServerPickerSheetState
    extends ConsumerState<_SftpServerPickerSheet> {
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

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.64,
        minChildSize: 0.38,
        maxChildSize: 0.86,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: _SftpPalette.canvas,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: _SftpPalette.border)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _SftpPalette.strongBorder,
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
                              l.tr('sftp.sheetTitle'),
                              style: const TextStyle(
                                color: _SftpPalette.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l.tr('sftp.sheetSubtitle'),
                              style: const TextStyle(
                                color: _SftpPalette.softMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SftpSheetIconButton(
                        tooltip: l.tr('common.close'),
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
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
                      cursorColor: _SftpPalette.primary,
                      style: const TextStyle(
                        color: _SftpPalette.text,
                        fontSize: 14,
                      ),
                      decoration: _sftpSearchDecoration(
                        hintText: l.tr('sftp.searchHint'),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                ),
                Expanded(
                  child: hostsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: _SftpPalette.primary,
                      ),
                    ),
                    error: (error, _) => ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _SftpPalette.muted),
                        ),
                        const SizedBox(height: 8),
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
          );
        },
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
            style: const TextStyle(color: _SftpPalette.muted),
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
          _SftpSectionLabel(l.tr('sftp.connectedSection')),
          for (final server in connected)
            _SftpServerRow(
              server: server,
              connected: true,
              active: server.id == widget.activeServerId,
              onTap: () => Navigator.of(context).pop(server),
            ),
        ],
        if (disconnected.isNotEmpty) ...[
          _SftpSectionLabel(l.tr('sftp.disconnectedSection')),
          for (final server in disconnected)
            _SftpServerRow(
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
    if (_query.isEmpty) return servers;
    return servers
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

class _SftpSectionLabel extends StatelessWidget {
  const _SftpSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _SftpPalette.softMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SftpServerRow extends StatelessWidget {
  const _SftpServerRow({
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
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: active || connected ? _SftpPalette.banner : _SftpPalette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _SftpPalette.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: connected ? _SftpPalette.card : _SftpPalette.chip,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.dns_outlined,
                      size: 21,
                      color: connected
                          ? _SftpPalette.primary
                          : _SftpPalette.muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _SftpPalette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          server.connectionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _SftpPalette.softMuted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (active)
                    const Icon(
                      Icons.check_rounded,
                      color: _SftpPalette.success,
                      size: 20,
                    )
                  else
                    _SftpStatusPill(
                      label: connected
                          ? l.tr('sftp.statusConnected')
                          : l.tr('sftp.statusDisconnected'),
                      connected: connected,
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

class _SftpStatusPill extends StatelessWidget {
  const _SftpStatusPill({required this.label, required this.connected});

  final String label;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final foreground = connected ? _SftpPalette.success : _SftpPalette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFEAF3E4) : _SftpPalette.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SftpSheetIconButton extends StatelessWidget {
  const _SftpSheetIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _SftpPalette.chip,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: _SftpPalette.muted, size: 18),
          ),
        ),
      ),
    );
  }
}

class _SftpMessageList extends StatelessWidget {
  const _SftpMessageList({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 56),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _SftpPalette.muted),
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 8),
          Center(child: action),
        ],
      ],
    );
  }
}

InputDecoration _sftpSearchDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    filled: true,
    fillColor: _SftpPalette.chip,
    prefixIcon: const Icon(
      Icons.search_rounded,
      size: 18,
      color: _SftpPalette.softMuted,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    hintStyle: const TextStyle(color: _SftpPalette.softMuted, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _SftpPalette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _SftpPalette.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _SftpPalette.border),
    ),
  );
}

abstract final class _SftpPalette {
  static const canvas = Color(0xFFF7EFE0);
  static const card = Color(0xFFFBF5E6);
  static const chip = Color(0xFFF4ECD7);
  static const banner = Color(0xFFF7E4B0);
  static const gold = Color(0xFFE5B33A);
  static const primary = Color(0xFF5C4520);
  static const text = Color(0xFF2A2418);
  static const muted = Color(0xFF6B5E3F);
  static const softMuted = Color(0xFF9A8B68);
  static const border = Color(0xFFE2D5B3);
  static const strongBorder = Color(0xFFC9B98D);
  static const success = Color(0xFF5A8E3A);
  static const danger = Color(0xFFC0392B);
}
