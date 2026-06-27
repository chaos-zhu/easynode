import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../features/servers/server_model.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/terminal_providers.dart';
import 'editor/text_editor_page.dart';
import 'media/image_preview_page.dart';
import 'media/media_extensions.dart';
import 'sftp_session_manager.dart';
import 'tab_header.dart';

class SftpTab extends StatelessWidget {
  const SftpTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: const SftpPanel(showHeader: true),
    );
  }
}

class SftpPanel extends ConsumerStatefulWidget {
  const SftpPanel({
    super.key,
    this.showHeader = false,
    this.initialHostId,
    this.allowDisconnect = true,
    this.lockToHost = false,
  });

  final bool showHeader;
  final String? initialHostId;
  final bool allowDisconnect;
  final bool lockToHost;

  @override
  ConsumerState<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends ConsumerState<SftpPanel> {
  bool _connecting = false;
  String? _autoConnectAttemptedHostId;

  Future<void> _refresh() => runRefreshWithFeedback(
    context,
    () => ref.read(hostListProvider.notifier).refresh(throwOnError: true),
  );

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
      if (error is SftpConnectTimeoutException) {
        _showSnack(l.tr('sftp.connectTimeout'));
      } else {
        _showSnack(error.toString());
      }
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

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final session = manager.activeSession;
        final showSelector =
            !widget.lockToHost &&
            !_connecting &&
            session != null &&
            session.status != SftpConnectionStatus.connecting;
        return Column(
          children: [
            if (widget.showHeader)
              TabHeader(
                title: l.tr('tabs.sftp'),
                actions: showSelector
                    ? [
                        _SftpHeaderSelector(
                          session: session,
                          onTap: _openServerPicker,
                          onDisconnect: widget.allowDisconnect
                              ? () => manager.disconnectActive()
                              : null,
                        ),
                      ]
                    : const [],
              ),
            if (!widget.showHeader && showSelector)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _SftpHeaderSelector(
                    session: session,
                    onTap: _openServerPicker,
                    onDisconnect: widget.allowDisconnect
                        ? () => manager.disconnectActive()
                        : null,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.card,
                onRefresh: _refresh,
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
                    return _SftpMessageList(
                      message: error.toString(),
                      action: TextButton(
                        onPressed: _refresh,
                        child: Text(l.tr('common.retry')),
                      ),
                    );
                  },
                  data: (servers) {
                    _autoConnectInitialServer(servers);
                    if (_connecting ||
                        session?.status == SftpConnectionStatus.connecting) {
                      return _SftpConnectingView(
                        server: session?.server,
                        phase: session?.connectPhase,
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
                              child: _SftpEmptyCard(
                                onChooseServer: _openServerPicker,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    if (session.status == SftpConnectionStatus.error) {
                      return _SftpMessageList(
                        message: session.lastError == 'timeout'
                            ? l.tr('sftp.connectTimeout')
                            : (session.lastError ?? l.tr('sftp.connectFailed')),
                        action: TextButton(
                          onPressed: () => _connectOrActivate(session.server),
                          child: Text(l.tr('common.retry')),
                        ),
                      );
                    }
                    return _SftpConnectedView(
                      session: session,
                      manager: manager,
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
    if (hostId == null || hostId.isEmpty) return;
    if (_autoConnectAttemptedHostId == hostId) return;
    final manager = ref.read(sftpSessionManagerProvider);
    if (manager.activeHostId == hostId && manager.activeSession != null) {
      _autoConnectAttemptedHostId = hostId;
      return;
    }
    ServerModel? target;
    for (final server in servers) {
      if (server.id == hostId) {
        target = server;
        break;
      }
    }
    final targetServer = target;
    if (targetServer == null) return;
    _autoConnectAttemptedHostId = hostId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connectOrActivate(targetServer);
    });
  }
}

class _SftpConnectedView extends StatelessWidget {
  const _SftpConnectedView({required this.session, required this.manager});

  final SftpSessionState session;
  final SftpSessionManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final showDirectoryLoading =
            session.loadingDirectory && session.showDirectoryLoading;
        return Column(
          children: [
            _SftpToolbar(session: session, manager: manager),
            _SftpPathBar(session: session, manager: manager),
            _SftpTableHeader(
              allSelected: session.allVisibleSelected,
              onSelectAll: session.toggleAllVisible,
            ),
            Expanded(
              child: Stack(
                children: [
                  if (session.entries.isEmpty && !showDirectoryLoading)
                    _SftpMessageList(
                      message: AppLocalizations.of(
                        context,
                      ).tr('sftp.emptyDirectory'),
                    )
                  else
                    ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
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
                            } else if (SftpSessionManager.isCompressedFile(
                              entry.name,
                            )) {
                              _promptAndExtract(context, session, entry);
                            } else {
                              _openFile(context, manager, session, entry);
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
                  if (showDirectoryLoading)
                    Positioned.fill(
                      child: ColoredBox(
                        color: context.colors.canvas.withValues(alpha: 0.27),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: context.colors.primary,
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

  Future<void> _openFile(
    BuildContext context,
    SftpSessionManager manager,
    SftpSessionState session,
    SftpFileEntry entry,
  ) async {
    final remotePath = manager.entryPath(session, entry);
    List<SftpFileEntry>? imageSiblings;
    var initialImageIndex = 0;
    if (isImageFileName(entry.name)) {
      final images = session.entries
          .where((e) => !e.isDirectory && isImageFileName(e.name))
          .toList(growable: false);
      final index = images.indexWhere((e) => e.name == entry.name);
      if (index >= 0) {
        imageSiblings = images;
        initialImageIndex = index;
      }
    }
    final mutatedFile = await _openRemoteFile(
      context: context,
      manager: manager,
      remotePath: remotePath,
      entry: entry,
      directoryPath: session.currentPath,
      imageSiblings: imageSiblings,
      initialImageIndex: initialImageIndex,
    );
    if (!context.mounted) return;
    if (mutatedFile) {
      await manager.refreshActive(showLoading: false);
    }
  }

  void _showFileActionSheet(
    BuildContext context,
    SftpSessionState session,
    SftpFileEntry anchor,
  ) {
    final l = AppLocalizations.of(context);
    final selectedEntries = session.entries
        .where((entry) => session.selectedNames.contains(entry.name))
        .toList(growable: false);
    final multi = selectedEntries.length > 1;
    final canExtract =
        !multi &&
        selectedEntries.length == 1 &&
        !selectedEntries.first.isDirectory &&
        SftpSessionManager.isCompressedFile(selectedEntries.first.name);
    final actions = <_SftpMenuAction>[
      _SftpMenuAction(
        Icons.download_outlined,
        l.tr('sftp.action.download'),
        _SftpMenuActionType.download,
      ),
      _SftpMenuAction(
        Icons.copy_outlined,
        l.tr('sftp.action.copyTo'),
        _SftpMenuActionType.copyTo,
      ),
      _SftpMenuAction(
        Icons.drive_file_move_outline,
        l.tr('sftp.action.moveTo'),
        _SftpMenuActionType.moveTo,
      ),
      _SftpMenuAction(
        Icons.archive_outlined,
        l.tr('sftp.action.compress'),
        _SftpMenuActionType.compress,
      ),
      if (canExtract)
        _SftpMenuAction(
          Icons.unarchive_outlined,
          l.tr('sftp.action.extract'),
          _SftpMenuActionType.extract,
        ),
      _SftpMenuAction(
        Icons.delete_outline,
        l.tr('sftp.action.delete'),
        _SftpMenuActionType.delete,
        destructive: true,
      ),
      if (!multi)
        _SftpMenuAction(
          Icons.edit_outlined,
          l.tr('sftp.action.rename'),
          _SftpMenuActionType.rename,
        ),
      if (!multi)
        _SftpMenuAction(
          Icons.link_outlined,
          l.tr('sftp.action.copyPath'),
          _SftpMenuActionType.copyPath,
        ),
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
            color: context.colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.strongBorder),
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
                        ? context.colors.danger
                        : context.colors.muted,
                  ),
                  title: Text(
                    action.label,
                    style: TextStyle(
                      color: action.destructive
                          ? context.colors.danger
                          : context.colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _handleAction(
                      context,
                      action.type,
                      session,
                      selectedEntries,
                      anchor,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _SftpMenuActionType type,
    SftpSessionState session,
    List<SftpFileEntry> entries,
    SftpFileEntry anchor,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      switch (type) {
        case _SftpMenuActionType.download:
          await _downloadEntries(context, session, entries);
        case _SftpMenuActionType.copyTo:
          final target = await _chooseRemoteDirectory(
            context,
            session.currentPath,
          );
          if (target == null) return;
          await manager.copyEntries(entries, target);
        case _SftpMenuActionType.moveTo:
          final target = await _chooseRemoteDirectory(
            context,
            session.currentPath,
          );
          if (target == null) return;
          await manager.moveEntries(entries, target);
        case _SftpMenuActionType.compress:
          final defaultName = entries.length == 1
              ? '${entries.first.name}.zip'
              : 'archive.zip';
          final name = await _showTextInputDialog(
            context,
            title: l.tr('sftp.compressTitle'),
            hint: l.tr('sftp.nameHint'),
            initialValue: defaultName,
          );
          if (name == null || name.trim().isEmpty) return;
          await manager.compressEntriesToCurrentDirectory(
            entries,
            zipName: name.trim(),
          );
        case _SftpMenuActionType.extract:
          await _promptAndExtract(context, session, anchor);
        case _SftpMenuActionType.delete:
          final confirmed = await _showDeleteConfirm(context, entries.length);
          if (!confirmed) return;
          await manager.deleteEntries(entries);
        case _SftpMenuActionType.rename:
          final name = await _showTextInputDialog(
            context,
            title: l.tr('sftp.renameTitle'),
            hint: l.tr('sftp.nameHint'),
            initialValue: anchor.name,
          );
          if (name == null || name.trim().isEmpty) return;
          await manager.renameEntry(anchor, name.trim());
        case _SftpMenuActionType.copyPath:
          await Clipboard.setData(
            ClipboardData(
              text: SftpSessionManager.joinPath(
                session.currentPath,
                anchor.name,
              ),
            ),
          );
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.tr('sftp.pathCopied'))));
          }
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _downloadEntries(
    BuildContext context,
    SftpSessionState session,
    List<SftpFileEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final l = AppLocalizations.of(context);
    final downloadDir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}sftp-downloads',
    );
    await downloadDir.create(recursive: true);
    late final File output;
    if (entries.length == 1 && !entries.first.isDirectory) {
      final entry = entries.first;
      output = File(
        '${downloadDir.path}${Platform.pathSeparator}${_safeFileName(entry.name)}',
      );
      final bytes = await manager.downloadFileBytes(
        SftpSessionManager.joinPath(session.currentPath, entry.name),
      );
      await output.writeAsBytes(bytes, flush: true);
    } else {
      final name = entries.length == 1
          ? '${entries.first.name}.zip'
          : 'sftp-${DateTime.now().millisecondsSinceEpoch}.zip';
      output = File(
        '${downloadDir.path}${Platform.pathSeparator}${_safeFileName(name)}',
      );
      final bytes = await manager.zipEntries(entries);
      await output.writeAsBytes(bytes, flush: true);
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(output.path)],
        text: l.tr('sftp.downloadReady'),
      ),
    );
  }

  Future<String?> _chooseRemoteDirectory(
    BuildContext context,
    String initialPath,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _SftpDirectoryPickerSheet(manager: manager, initialPath: initialPath),
    );
  }

  Future<bool> _showDeleteConfirm(BuildContext context, int count) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l.tr('sftp.deleteTitle')),
            content: Text(l.tr('sftp.deleteBody').replaceAll('{0}', '$count')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l.tr('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l.tr('common.delete')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _showTextInputDialog(
    BuildContext context, {
    required String title,
    required String hint,
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _SftpNameDialog(title: title, hint: hint, initialValue: initialValue),
    );
  }

  Future<void> _promptAndExtract(
    BuildContext context,
    SftpSessionState session,
    SftpFileEntry entry,
  ) async {
    final l = AppLocalizations.of(context);
    final target = await _showTextInputDialog(
      context,
      title: l.tr('sftp.extractToTitle'),
      hint: l.tr('sftp.extractPathHint'),
      initialValue: session.currentPath,
    );
    if (target == null || target.trim().isEmpty) return;
    try {
      await manager.extractEntry(entry, destDir: target.trim());
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.tr('sftp.extractDone'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

Future<bool> _openRemoteFile({
  required BuildContext context,
  required SftpSessionManager manager,
  required String remotePath,
  required SftpFileEntry entry,
  required String directoryPath,
  List<SftpFileEntry>? imageSiblings,
  int initialImageIndex = 0,
}) async {
  final Widget page;
  var mayMutate = false;
  if (isImageFileName(entry.name)) {
    page = SftpImagePreviewPage(
      manager: manager,
      directoryPath: directoryPath,
      images: imageSiblings ?? [entry],
      initialIndex: imageSiblings == null ? 0 : initialImageIndex,
    );
  } else {
    page = TextEditorPage(
      manager: manager,
      remotePath: remotePath,
      fileName: entry.name,
    );
    mayMutate = true;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  return mayMutate;
}

class _SftpMenuAction {
  const _SftpMenuAction(
    this.icon,
    this.label,
    this.type, {
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final _SftpMenuActionType type;
  final bool destructive;
}

enum _SftpMenuActionType {
  download,
  copyTo,
  moveTo,
  compress,
  extract,
  delete,
  rename,
  copyPath,
}

class _SftpHeaderSelector extends StatelessWidget {
  const _SftpHeaderSelector({
    required this.session,
    required this.onTap,
    required this.onDisconnect,
  });

  final SftpSessionState session;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isError = session.status == SftpConnectionStatus.error;
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
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: c.muted,
                  ),
                  if (onDisconnect != null) ...[
                    const SizedBox(width: 2),
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
    final l = AppLocalizations.of(context);
    _showOptionSheet(context, [
      _SftpSheetAction(Icons.upload_file_outlined, l.tr('sftp.uploadFile'), () {
        _uploadFiles(context);
      }),
      _SftpSheetAction(
        Icons.create_new_folder_outlined,
        l.tr('sftp.uploadFolder'),
        () {
          _uploadFolder(context);
        },
      ),
    ]);
  }

  Future<void> _uploadFiles(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      final paths =
          result?.paths.whereType<String>().toList(growable: false) ??
          const <String>[];
      if (paths.isEmpty) return;
      await manager.uploadFiles(paths.map(File.new).toList(growable: false));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _uploadFolder(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null) return;
      final directory = Directory(path);
      if (!await directory.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.tr('sftp.folderUploadUnsupported'))),
        );
        return;
      }
      await manager.uploadDirectory(directory);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showCreateMenu(BuildContext context) {
    final l = AppLocalizations.of(context);
    _showOptionSheet(context, [
      _SftpSheetAction(
        Icons.insert_drive_file_outlined,
        l.tr('sftp.newFile'),
        () {
          _showNameDialog(context, type: 'file');
        },
      ),
      _SftpSheetAction(
        Icons.create_new_folder_outlined,
        l.tr('sftp.newFolder'),
        () {
          _showNameDialog(context, type: 'folder');
        },
      ),
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
          () => _openFavorite(context, favorite),
        ),
    ]);
  }

  Future<void> _openFavorite(
    BuildContext context,
    SftpFavorite favorite,
  ) async {
    if (favorite.type == 'folder') {
      await manager.openPath(favorite.path);
      return;
    }
    final parent = SftpSessionManager.parentPath(favorite.path);
    final fileName = _favoriteBasename(favorite.path);
    await manager.openPath(parent);
    if (!context.mounted) return;
    final entry = SftpFileEntry(
      name: fileName,
      type: '-',
      size: null,
      modifyTime: null,
      permissions: '',
      ownerName: '',
      groupName: '',
    );
    final mutatedFile = await _openRemoteFile(
      context: context,
      manager: manager,
      remotePath: favorite.path,
      entry: entry,
      directoryPath: parent,
    );
    if (!context.mounted) return;
    if (mutatedFile) {
      await manager.refreshActive(showLoading: false);
    }
  }

  String _favoriteBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final index = trimmed.lastIndexOf('/');
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }

  Future<void> _showNameDialog(
    BuildContext context, {
    required String type,
  }) async {
    final l = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SftpNameDialog(
        title: type == 'folder' ? l.tr('sftp.newFolder') : l.tr('sftp.newFile'),
        hint: l.tr('sftp.nameHint'),
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
    final c = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.strongBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                ListTile(
                  dense: true,
                  leading: Icon(action.icon, color: c.muted),
                  title: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
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
    final c = context.colors;
    return Expanded(
      child: Material(
        color: enabled ? c.card : c.chip,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
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
                    color: enabled ? c.text : c.softMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: enabled ? c.muted : c.softMuted,
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

class _SftpNameDialog extends StatefulWidget {
  const _SftpNameDialog({
    required this.title,
    required this.hint,
    this.initialValue = '',
  });

  final String title;
  final String hint;
  final String initialValue;

  @override
  State<_SftpNameDialog> createState() => _SftpNameDialogState();
}

class _SftpNameDialogState extends State<_SftpNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l.tr('common.save')),
        ),
      ],
    );
  }
}

class _SftpDirectoryPickerSheet extends StatefulWidget {
  const _SftpDirectoryPickerSheet({
    required this.manager,
    required this.initialPath,
  });

  final SftpSessionManager manager;
  final String initialPath;

  @override
  State<_SftpDirectoryPickerSheet> createState() =>
      _SftpDirectoryPickerSheetState();
}

class _SftpDirectoryPickerSheetState extends State<_SftpDirectoryPickerSheet> {
  late String _path;
  var _directories = const <SftpFileEntry>[];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final directories = await widget.manager.listDirectories(_path);
      if (!mounted) return;
      setState(() {
        _directories = directories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(String path) async {
    _path = path;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.42,
        maxChildSize: 0.9,
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.tr('sftp.chooseTargetFolder'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    _SftpIconAction(
                      icon: Icons.home_outlined,
                      onTap: () => _open('/'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _SftpIconAction(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _open(SftpSessionManager.parentPath(_path)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: c.primary))
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.muted),
                          ),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          for (final directory in _directories)
                            ListTile(
                              leading: Icon(
                                Icons.folder_rounded,
                                color: c.accent,
                              ),
                              title: Text(
                                directory.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => _open(
                                SftpSessionManager.joinPath(
                                  _path,
                                  directory.name,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_path),
                    child: Text(l.tr('sftp.selectThisFolder')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              child: Icon(
                Icons.home_outlined,
                size: 16,
                color: context.colors.muted,
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
    final c = context.colors;
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => manager.openPath('/'),
          child: Text(
            '/',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
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
      separatorBuilder: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: c.softMuted,
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
              style: TextStyle(
                color: c.text,
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
      child: Icon(icon, size: 18, color: context.colors.muted),
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
    final c = context.colors;
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Checkbox(
              value: allSelected,
              onChanged: (_) => onSelectAll(),
              activeColor: c.primary,
            ),
          ),
          Expanded(
            child: Text(
              '名称',
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '大小',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '时间',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.muted,
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
    final c = context.colors;
    return Material(
      color: selected ? c.banner : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onSelectionChanged(),
                  activeColor: c.primary,
                ),
              ),
              Icon(
                entry.isDirectory
                    ? Icons.folder_rounded
                    : entry.isLink
                    ? Icons.link_rounded
                    : Icons.insert_drive_file_outlined,
                size: 20,
                color: entry.isDirectory ? c.accent : c.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
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
                  style: TextStyle(color: c.softMuted, fontSize: 12),
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
                  style: TextStyle(color: c.softMuted, fontSize: 10),
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
  const _SftpConnectingView({required this.server, this.phase});

  final ServerModel? server;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phaseLabel = switch (phase) {
      'transport' => l.tr('sftp.phase.transport'),
      'channel' => l.tr('sftp.phase.channel'),
      'listing' => l.tr('sftp.phase.listing'),
      _ => l.tr('sftp.connecting'),
    };
    final c = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 110),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  color: c.primary,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                phaseLabel,
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                server?.displayName ?? '',
                style: TextStyle(
                  color: c.softMuted,
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
    final c = context.colors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420, minHeight: 348),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _SftpOrbitIcon(),
          const SizedBox(height: 18),
          SizedBox(
            height: 24,
            child: Text(
              l.tr('sftp.emptyTitle'),
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
              l.tr('sftp.emptyBody'),
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
          _SftpPrimaryButton(
            icon: Icons.folder_outlined,
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
    final c = context.colors;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 14,
            child: _SftpDot(size: 10, color: c.banner),
          ),
          Positioned(
            right: 12,
            top: 8,
            child: _SftpDot(size: 8, color: c.accent),
          ),
          Positioned(
            right: 4,
            bottom: 12,
            child: _SftpDot(size: 12, color: c.banner),
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
                color: c.banner,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x66E5B33A)),
              ),
              child: Icon(Icons.folder_rounded, color: c.primary, size: 42),
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
              Icon(icon, size: 16, color: c.fontOnPrimary),
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
    final c = context.colors;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.64,
        minChildSize: 0.38,
        maxChildSize: 0.86,
        expand: false,
        builder: (context, scrollController) {
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('sftp.sheetTitle'),
                              style: TextStyle(
                                color: c.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l.tr('sftp.sheetSubtitle'),
                              style: TextStyle(
                                color: c.softMuted,
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
                      cursorColor: c.primary,
                      style: TextStyle(color: c.text, fontSize: 14),
                      decoration: _sftpSearchDecoration(
                        context,
                        hintText: l.tr('sftp.searchHint'),
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
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.muted),
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
        style: TextStyle(
          color: context.colors.softMuted,
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
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: active || connected ? c.banner : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
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
                      color: connected ? c.card : c.chip,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      size: 21,
                      color: connected ? c.primary : c.muted,
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
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          server.connectionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.softMuted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (active)
                    Icon(Icons.check_rounded, color: c.success, size: 20)
                  else if (!connected)
                    _SftpStatusPill(
                      label: l.tr('sftp.statusDisconnected'),
                      connected: false,
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
    final c = context.colors;
    final foreground = connected ? c.success : c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: connected ? c.success.withValues(alpha: 0.15) : c.chip,
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
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.chip,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: c.muted, size: 18),
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
            style: TextStyle(color: context.colors.muted),
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

InputDecoration _sftpSearchDecoration(
  BuildContext context, {
  required String hintText,
}) {
  final c = context.colors;
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    filled: true,
    fillColor: c.chip,
    prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.softMuted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    hintStyle: TextStyle(color: c.softMuted, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
  );
}

String _safeFileName(String name) {
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
