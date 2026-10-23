import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as local;

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../core/ui/desktop_popover.dart';
import '../../../state/api_providers.dart';
import '../../servers/server_model.dart';
import '../../shell/editor/editor_language.dart';
import 'desktop_sftp_editor.dart';
import '../../shell/media/image_preview_page.dart';
import '../../shell/media/media_extensions.dart';
import '../../shell/sftp_session_manager.dart';
import 'desktop_terminal_settings.dart';
import 'sftp_transfer_queue.dart';
import 'terminal_text_prompt.dart';
import 'terminal_widgets.dart';

/// Desktop presentation over the same direct-SFTP service used on mobile.
class DesktopSftpPanel extends ConsumerStatefulWidget {
  const DesktopSftpPanel({
    super.key,
    required this.server,
    required this.manager,
    this.onExecCommand,
    this.pathRequest,
  });
  final ServerModel server;
  final SftpSessionManager manager;
  final ValueChanged<String>? onExecCommand;
  final ValueListenable<String?>? pathRequest;
  @override
  ConsumerState<DesktopSftpPanel> createState() => _DesktopSftpPanelState();
}

class _DesktopSftpPanelState extends ConsumerState<DesktopSftpPanel> {
  final _path = TextEditingController();
  final _query = TextEditingController();
  final _transfers = SftpTransferQueue();
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  String _sort = 'name';
  bool _ascending = true, _editingPath = false, _tasksVisible = false;
  String? _selectionAnchor;
  String? _pendingPath;
  SftpSessionManager get manager => widget.manager;
  SftpSessionState? get session => manager.sessionFor(widget.server.id);
  String _t(String key) => dt(context, 'sftp.$key');
  static const _optionalColumns = [
    'size',
    'modified',
    'permissions',
    'owner',
    'group',
  ];

  @override
  void initState() {
    super.initState();
    _pendingPath = widget.pathRequest?.value;
    widget.pathRequest?.addListener(_pathRequested);
    Future.microtask(_connect);
  }

  @override
  void dispose() {
    widget.pathRequest?.removeListener(_pathRequested);
    _path.dispose();
    _query.dispose();
    _transfers.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _pathRequested() {
    final path = widget.pathRequest?.value;
    if (path == null) return;
    _pendingPath = path;
    if (session?.isConnected == true) unawaited(_run(_applyRequestedPath));
  }

  Future<void> _applyRequestedPath() async {
    final path = _pendingPath;
    _pendingPath = null;
    if (path != null) await manager.openPath(path);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) terminalNotice(context, error.toString());
    }
  }

  Future<void> _connect({bool reconnect = false}) async {
    await _run(() async {
      if (reconnect) await manager.disconnect(widget.server.id);
      if (!mounted) return;
      if (manager.isConnected(widget.server.id)) {
        manager.activate(widget.server.id);
        await _applyRequestedPath();
        return;
      }
      final repository = ref.read(serverRepositoryProvider);
      final config = await repository.fetchSshConfig(widget.server.id);
      if (!mounted) return;
      await manager.connect(
        server: widget.server,
        config: config,
        loadFavorites: repository.fetchSftpFavorites,
      );
      if (mounted &&
          ref.read(desktopTerminalPreferencesProvider)['sftpHidden'] == true) {
        await manager.setShowHidden(true);
      }
      await _applyRequestedPath();
    });
  }

  Future<void> _persist(String key, Object value) => _run(
    () => ref.read(desktopTerminalPreferencesProvider.notifier).set(key, value),
  );
  Future<void> _reloadFavorites() async {
    final favorites = await ref
        .read(serverRepositoryProvider)
        .fetchSftpFavorites(widget.server.id);
    session?.update(favorites: favorites);
  }

  Future<void> _favorite(String path, String name, bool directory) =>
      _run(() async {
        final api = ref.read(apiClientProvider);
        final endpoint =
            '/sftp/favorites/${Uri.encodeComponent(widget.server.id)}';
        if (session!.favorites.any((f) => f.path == path)) {
          await api.deleteJson(endpoint, queryParameters: {'path': path});
        } else {
          await api.postJson(endpoint, {
            'path': path,
            'name': name,
            'type': directory ? 'folder' : 'file',
          });
        }
        await _reloadFavorites();
      });
  Future<void> _favorites(BuildContext anchor) async {
    await _run(() async {
      await _reloadFavorites();
      if (!mounted || !anchor.mounted) return;
      final selected = await showDesktopPopover<SftpFavorite>(
        context: anchor,
        width: 330,
        maxHeight: 400,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(6),
            children: [
              if (session!.favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_t('noFavorites')),
                ),
              for (final favorite in session!.favorites)
                ListTile(
                  dense: true,
                  leading: Icon(
                    favorite.type == 'folder' || favorite.type == 'd'
                        ? Icons.folder_outlined
                        : Icons.description_outlined,
                    size: 17,
                  ),
                  title: Text(
                    favorite.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    favorite.path,
                    style: const TextStyle(fontSize: 10),
                  ),
                  onTap: () => Navigator.pop(context, favorite),
                  trailing: IconButton(
                    icon: const Icon(Icons.star, size: 15),
                    tooltip: _t('unfavorite'),
                    onPressed: () async {
                      await _favorite(
                        favorite.path,
                        favorite.name,
                        favorite.type == 'folder',
                      );
                      if (context.mounted) update(() {});
                    },
                  ),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      if (selected.type == 'folder' || selected.type == 'd') {
        await manager.openPath(selected.path);
      } else {
        await manager.openPath(SftpSessionManager.parentPath(selected.path));
        final entry = session!.entries
            .where((e) => e.name == local.posix.basename(selected.path))
            .firstOrNull;
        if (entry != null && mounted) await _open(entry);
      }
    });
  }

  List<SftpFileEntry> _entries() {
    final query = _query.text.trim().toLowerCase();
    final entries = (session?.entries ?? [])
        .where((e) => e.name.toLowerCase().contains(query))
        .toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final comparison = switch (_sort) {
        'size' => (a.size ?? 0).compareTo(b.size ?? 0),
        'modified' => (a.modifyTime ?? DateTime(0)).compareTo(
          b.modifyTime ?? DateTime(0),
        ),
        'permissions' => a.permissions.compareTo(b.permissions),
        'owner' => a.ownerName.compareTo(b.ownerName),
        'group' => a.groupName.compareTo(b.groupName),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return _ascending ? comparison : -comparison;
    });
    return entries;
  }

  List<SftpFileEntry> get _selected => session!.entries
      .where((e) => session!.selectedNames.contains(e.name))
      .toList();
  void _select(
    SftpFileEntry entry,
    List<SftpFileEntry> visible, {
    bool toggle = false,
  }) {
    final keys = HardwareKeyboard.instance;
    final anchor = visible.indexWhere((e) => e.name == _selectionAnchor);
    if (keys.isShiftPressed && anchor >= 0) {
      final index = visible.indexOf(entry);
      session!.update(
        selectedNames: visible
            .sublist(math.min(anchor, index), math.max(anchor, index) + 1)
            .map((e) => e.name)
            .toSet(),
      );
    } else if (toggle || keys.isControlPressed || keys.isMetaPressed) {
      session!.toggleSelection(entry.name);
      _selectionAnchor = entry.name;
    } else {
      session!.selectOnly(entry.name);
      _selectionAnchor = entry.name;
    }
  }

  Future<void> _open(SftpFileEntry entry, {bool edit = false}) =>
      _run(() async {
        final path = manager.entryPath(session!, entry);
        if (entry.isDirectory ||
            entry.isLink && await manager.isRemoteDirectory(path)) {
          await manager.openPath(path);
          return;
        }
        if (!mounted) return;
        if (!edit &&
            isKnownBinaryExtension(entry.name) &&
            !isImageFileName(entry.name)) {
          terminalNotice(context, _t('binaryDownload'));
          return;
        }
        final images = session!.entries
            .where((e) => !e.isDirectory && isImageFileName(e.name))
            .toList();
        final image = !edit && isImageFileName(entry.name);
        await showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          closeOnPressEscape: false,
          builder: (context) => image
              ? Dialog(
                  insetPadding: const EdgeInsets.all(28),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 1200,
                    height: MediaQuery.sizeOf(context).height * .88,
                    child: SftpImagePreviewPage(
                      manager: manager,
                      directoryPath: session!.currentPath,
                      images: images,
                      initialIndex: images.indexOf(entry),
                    ),
                  ),
                )
              : DesktopSftpEditor(
                  manager: manager,
                  remotePath: path,
                  fileName: entry.name,
                ),
        );
        await manager.refreshActive(showLoading: false);
      });
  String? _validateName(String value) =>
      value.isEmpty ||
          value == '.' ||
          value == '..' ||
          value.contains('/') ||
          value.contains('\\')
      ? _t('invalidName')
      : null;
  Future<void> _create(BuildContext anchor) async {
    final action = await showTerminalMenu(anchor, [
      TerminalMenuAction('file', _t('newFile'), Icons.note_add_outlined),
      TerminalMenuAction(
        'directory',
        _t('newDirectory'),
        Icons.create_new_folder_outlined,
      ),
    ]);
    if (!mounted || action == null) return;
    final name = await terminalTextPrompt(
      context,
      title: _t(action == 'file' ? 'newFile' : 'newDirectory'),
      validate: _validateName,
    );
    if (name != null) {
      await _run(
        () => action == 'file'
            ? manager.createFile(name)
            : manager.createDirectory(name),
      );
    }
  }

  Future<bool> _confirm(String body) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (context) => DesktopManagementDialog(
          title: dt(context, 'confirm'),
          width: 460,
          body: Text(body, style: const TextStyle(fontSize: 13)),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dt(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(dt(context, 'confirm')),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _context(SftpFileEntry entry, Offset position) async {
    if (!session!.selectedNames.contains(entry.name)) {
      session!.selectOnly(entry.name);
    }
    final entries = _selected;
    final single = entries.length == 1;
    final path = manager.entryPath(session!, entry);
    final favorite = session!.favorites.any((f) => f.path == path);
    final compose =
        single &&
        RegExp(
          r'^(docker-)?compose[^/]*\.ya?ml$',
          caseSensitive: false,
        ).hasMatch(entry.name);
    final action = await showTerminalMenu(context, [
      if (single)
        TerminalMenuAction(
          'open',
          _t(entry.isDirectory ? 'open' : 'edit'),
          Icons.open_in_new,
        ),
      TerminalMenuAction('download', _t('download'), Icons.download_outlined),
      TerminalMenuAction('copy', _t('copyTo'), Icons.copy_outlined),
      TerminalMenuAction('move', _t('moveTo'), Icons.drive_file_move_outline),
      TerminalMenuAction('compress', _t('compress'), Icons.folder_zip_outlined),
      if (single && SftpSessionManager.isCompressedFile(entry.name))
        TerminalMenuAction('extract', _t('extract'), Icons.unarchive_outlined),
      if (single) ...[
        TerminalMenuAction(
          'rename',
          _t('rename'),
          Icons.drive_file_rename_outline,
        ),
        TerminalMenuAction(
          'favorite',
          _t(favorite ? 'unfavorite' : 'favorite'),
          Icons.star_outline,
        ),
        TerminalMenuAction('path', _t('copyPath'), Icons.content_copy),
        if (entry.isDirectory && widget.onExecCommand != null)
          TerminalMenuAction('terminal', _t('cdTerminal'), Icons.terminal),
      ],
      if (compose && widget.onExecCommand != null)
        for (final command in [
          'up',
          'restart',
          'down',
          'pull',
          'rebuild',
          'upgrade',
          'logs',
          'stop',
        ])
          TerminalMenuAction(
            'compose.$command',
            'Docker compose · ${dt(context, 'compose.$command')}',
            Icons.layers_outlined,
          ),
      TerminalMenuAction(
        'delete',
        _t('delete'),
        Icons.delete_outline,
        danger: true,
      ),
    ], position: position);
    if (!mounted) return;
    await _run(() async {
      switch (action) {
        case 'open':
          await _open(entry, edit: !entry.isDirectory);
        case 'download':
          await _download(entries);
        case 'copy':
        case 'move':
          final target = await terminalTextPrompt(
            context,
            title: _t(action == 'copy' ? 'copyTo' : 'moveTo'),
            value: session!.currentPath,
            hint: _t('remotePath'),
          );
          if (target != null) {
            if (action == 'copy') {
              await manager.copyEntries(entries, target);
            } else {
              await manager.moveEntries(entries, target);
            }
          }
        case 'compress':
          final name = await terminalTextPrompt(
            context,
            title: _t('compress'),
            value: 'archive.zip',
            validate: _validateName,
          );
          if (name != null) {
            await manager.compressEntriesToCurrentDirectory(
              entries,
              zipName: name,
            );
          }
        case 'extract':
          final target = await terminalTextPrompt(
            context,
            title: _t('extract'),
            value: session!.currentPath,
          );
          if (target != null) {
            await manager.extractEntry(entry, destDir: target);
          }
        case 'rename':
          final name = await terminalTextPrompt(
            context,
            title: _t('rename'),
            value: entry.name,
            validate: _validateName,
          );
          if (name != null) await manager.renameEntry(entry, name);
        case 'favorite':
          await _favorite(path, entry.name, entry.isDirectory);
        case 'path':
          await Clipboard.setData(ClipboardData(text: path));
        case 'terminal':
          widget.onExecCommand?.call('cd -- ${_quote(path)}');
        case 'delete':
          if (await _confirm(
            '${_t('deleteConfirm')} (${entries.map((e) => e.name).join(', ')})',
          )) {
            await manager.deleteEntries(entries);
          }
        default:
          if (action?.startsWith('compose.') == true) {
            final verb = action!.substring(8);
            final prefix = 'docker compose -f ${_quote(path)}';
            final command = switch (verb) {
              'up' => '$prefix up -d',
              'rebuild' => '$prefix up -d --build',
              'upgrade' => '$prefix pull && $prefix down && $prefix up -d',
              'logs' => '$prefix logs -f',
              _ => '$prefix $verb',
            };
            if (!['down', 'stop', 'rebuild', 'upgrade'].contains(verb) ||
                await _confirm(command)) {
              widget.onExecCommand?.call(command);
            }
          }
      }
    });
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
  void _queue(SftpTransferTask task) {
    _transfers.add(task);
    setState(() => _tasksVisible = true);
  }

  Future<void> _upload(BuildContext anchor) async {
    final action = await showTerminalMenu(anchor, [
      TerminalMenuAction(
        'files',
        _t('uploadFiles'),
        Icons.upload_file_outlined,
      ),
      TerminalMenuAction(
        'folder',
        _t('uploadDirectory'),
        Icons.drive_folder_upload_outlined,
      ),
    ]);
    if (!mounted || action == null) return;
    await _run(() async {
      final target = session!.currentPath;
      if (action == 'files') {
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          lockParentWindow: true,
        );
        if (result == null || !mounted) return;
        for (final file in result.files) {
          if (file.path != null) {
            _uploadFile(
              File(file.path!),
              SftpSessionManager.joinPath(target, file.name),
            );
          }
        }
      } else {
        final path = await FilePicker.getDirectoryPath(lockParentWindow: true);
        if (path == null || !mounted) return;
        final directory = Directory(path);
        final remoteRoot = SftpSessionManager.joinPath(
          target,
          local.basename(path),
        );
        // Capture the tree before queuing. Symlinks are never followed locally.
        final entities = await directory
            .list(recursive: true, followLinks: false)
            .toList();
        _queue(
          SftpTransferTask(
            name: local.basename(path),
            upload: true,
            run: (task) async {
              await manager.ensureRemoteDirectory(remoteRoot);
              final files = entities.whereType<File>().toList();
              final total = await files.fold<Future<int>>(
                Future.value(0),
                (sum, file) async => await sum + await file.length(),
              );
              var completed = 0;
              for (final entity in entities) {
                if (task.cancelRequested) throw const SftpTransferCancelled();
                final relative = local
                    .relative(entity.path, from: path)
                    .split(local.separator)
                    .join('/');
                final remote = SftpSessionManager.joinPath(
                  remoteRoot,
                  relative,
                );
                if (entity is Directory) {
                  await manager.ensureRemoteDirectory(remote);
                } else if (entity is File) {
                  await manager.uploadToRemoteFile(
                    remote,
                    entity,
                    shouldCancel: () => task.cancelRequested,
                    onProgress: (sent, _) =>
                        _transfers.progress(task, completed + sent, total),
                  );
                  completed += await entity.length();
                }
              }
              await manager.refreshActive(showLoading: false);
            },
          ),
        );
      }
    });
  }

  void _uploadFile(File file, String remote) => _queue(
    SftpTransferTask(
      name: local.basename(file.path),
      upload: true,
      run: (task) async {
        await manager.uploadToRemoteFile(
          remote,
          file,
          shouldCancel: () => task.cancelRequested,
          onProgress: (bytes, total) => _transfers.progress(task, bytes, total),
        );
        await manager.refreshActive(showLoading: false);
      },
    ),
  );
  Future<void> _download(List<SftpFileEntry> entries) async {
    final source = session!.currentPath;
    if (entries.length == 1 && !entries.first.isDirectory) {
      final entry = entries.first;
      final output = await FilePicker.saveFile(
        fileName: entry.name,
        lockParentWindow: true,
      );
      if (output != null && mounted) {
        _downloadFile(
          SftpSessionManager.joinPath(source, entry.name),
          File(output),
          entry.name,
        );
      }
      return;
    }
    final directory = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (directory == null || !mounted) return;
    for (final entry in entries) {
      final remote = SftpSessionManager.joinPath(source, entry.name);
      final destination = local.join(directory, entry.name);
      if (!entry.isDirectory) {
        _downloadFile(remote, File(destination), entry.name);
        continue;
      }
      _queue(
        SftpTransferTask(
          name: entry.name,
          upload: false,
          run: (task) async {
            var received = 0;
            Future<void> downloadTree(String path, String output) async {
              if (task.cancelRequested) throw const SftpTransferCancelled();
              await Directory(output).create(recursive: true);
              for (final child in await manager.listEntriesAt(path)) {
                final remoteChild = SftpSessionManager.joinPath(
                  path,
                  child.name,
                );
                final localChild = local.join(output, child.name);
                if (child.isDirectory) {
                  await downloadTree(remoteChild, localChild);
                } else if (!child.isLink) {
                  await manager.downloadToLocalFile(
                    remoteChild,
                    File(localChild),
                    shouldCancel: () => task.cancelRequested,
                    onProgress: (bytes, _) =>
                        _transfers.progress(task, received + bytes, null),
                  );
                  received += await File(localChild).length();
                }
              }
            }

            await downloadTree(remote, destination);
          },
        ),
      );
    }
  }

  void _downloadFile(String remote, File file, String name) => _queue(
    SftpTransferTask(
      name: name,
      upload: false,
      run: (task) => manager.downloadToLocalFile(
        remote,
        file,
        shouldCancel: () => task.cancelRequested,
        onProgress: (bytes, total) => _transfers.progress(task, bytes, total),
      ),
    ),
  );

  Future<void> _columns(BuildContext anchor) => showDesktopPopover<void>(
    context: anchor,
    width: 230,
    maxHeight: 360,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final saved = ref.watch(
          desktopTerminalPreferencesProvider,
        )['sftpColumns'];
        final columns = saved is List
            ? saved.cast<String>().toSet()
            : {'size', 'modified'};
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in _optionalColumns)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: columns.contains(key),
                title: Text(_t(key), style: const TextStyle(fontSize: 12)),
                onChanged: (value) {
                  final next = {...columns};
                  if (value!) {
                    next.add(key);
                  } else {
                    next.remove(key);
                  }
                  unawaited(_persist('sftpColumns', next.toList()));
                },
              ),
          ],
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([manager, _transfers]),
    builder: (context, _) {
      final state = session;
      return state == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: state,
              builder: (context, _) => _body(state),
            );
    },
  );
  Widget _body(SftpSessionState state) {
    final connected = state.isConnected;
    final preferences = ref.watch(desktopTerminalPreferencesProvider);
    final raw = preferences['sftpColumns'];
    final columns = raw is List
        ? raw.cast<String>().toSet()
        : {'size', 'modified'};
    final entries = _entries();
    return ColoredBox(
      color: context.colors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Builder(
                            builder: (anchor) => TerminalMenuButton(
                              label: _t('upload'),
                              outlined: true,
                              dropdown: true,
                              onPressed: connected
                                  ? () => _upload(anchor)
                                  : null,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Builder(
                            builder: (anchor) => TerminalMenuButton(
                              label: _t('create'),
                              outlined: true,
                              dropdown: true,
                              onPressed: connected
                                  ? () => _create(anchor)
                                  : null,
                            ),
                          ),
                        ),
                        if (state.favorites.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Builder(
                              builder: (anchor) => TerminalMenuButton(
                                label: _t('favorites'),
                                outlined: true,
                                dropdown: true,
                                onPressed: connected
                                    ? () => _favorites(anchor)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                TerminalToolButton(
                  icon: Icons.restart_alt,
                  label: dt(context, 'reconnect'),
                  color: context.colors.warning,
                  showLabel: false,
                  onPressed: () => _connect(reconnect: true),
                ),
              ],
            ),
          ),
          if (!connected)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.status == SftpConnectionStatus.connecting)
                        const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        state.lastError ??
                            dt(context, 'status.${state.status.name}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (state.status != SftpConnectionStatus.connecting)
                        TextButton(
                          onPressed: _connect,
                          child: Text(dt(context, 'retry')),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            _pathBar(state),
            SizedBox(
              height: 2,
              child: state.loadingDirectory
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            if (state.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.danger,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _run(manager.refreshActive),
                      child: Text(dt(context, 'retry')),
                    ),
                  ],
                ),
              ),
            Expanded(child: _table(entries, columns)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} ${_t('items')} · ${state.selectedNames.length} ${_t('selected')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                  if (state.hasSelection)
                    TerminalToolButton(
                      icon: Icons.download_outlined,
                      label: _t('download'),
                      showLabel: false,
                      onPressed: () => _run(() => _download(_selected)),
                    ),
                ],
              ),
            ),
          ],
          if (_tasksVisible) _transferList(),
        ],
      ),
    );
  }

  Future<void> _searchFiles(BuildContext anchor) => showDesktopPopover<void>(
    context: anchor,
    width: 260,
    maxHeight: 80,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(10),
      child: TextField(
        controller: _query,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: _t('search'),
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 15),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, size: 14),
            onPressed: () => setState(() => _query.clear()),
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    ),
  );

  Widget _pathBar(SftpSessionState state) => Container(
    height: 30,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        TerminalToolButton(
          icon: Icons.arrow_back,
          label: _t('parent'),
          showLabel: false,
          color: context.colors.accent,
          onPressed: () => _run(manager.goParent),
        ),
        Expanded(
          child: _editingPath
              ? TextField(
                  controller: _path,
                  autofocus: true,
                  onTapOutside: (_) {
                    if (mounted) setState(() => _editingPath = false);
                  },
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    setState(() => _editingPath = false);
                    unawaited(_run(() => manager.openPath(value.trim())));
                  },
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      TerminalToolButton(
                        icon: Icons.home,
                        label: '/',
                        color: context.colors.accent,
                        showLabel: false,
                        onPressed: () => _run(() => manager.openPath('/')),
                      ),
                      for (final segment in _breadcrumbs(
                        state.currentPath,
                      )) ...[
                        TerminalIcon(
                          Icons.arrow_forward,
                          size: 12,
                          color: context.colors.muted,
                        ),
                        TextButton(
                          onPressed: () =>
                              _run(() => manager.openPath(segment.$2)),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.accent,
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            segment.$1,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        TerminalToolButton(
          icon: Icons.edit_outlined,
          label: _t('editPath'),
          showLabel: false,
          color: context.colors.accent,
          onPressed: () {
            _path.text = state.currentPath;
            setState(() => _editingPath = true);
          },
        ),
        if (_transfers.tasks.isNotEmpty)
          TerminalToolButton(
            icon: Icons.swap_vert,
            label: _t('transfers'),
            selected: _tasksVisible,
            color: context.colors.success,
            showLabel: false,
            onPressed: () => setState(() => _tasksVisible = !_tasksVisible),
          ),
        Builder(
          builder: (anchor) => TerminalToolButton(
            icon: Icons.search,
            label: _t('search'),
            showLabel: false,
            color: context.colors.accent,
            selected: _query.text.isNotEmpty,
            onPressed: () => _searchFiles(anchor),
          ),
        ),
        TerminalToolButton(
          icon: Icons.copy_outlined,
          label: _t('copyPath'),
          showLabel: false,
          color: context.colors.accent,
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: state.currentPath)),
        ),
        TerminalToolButton(
          icon: Icons.refresh,
          label: _t('refresh'),
          showLabel: false,
          color: context.colors.accent,
          onPressed: () => _run(manager.refreshActive),
        ),
        TerminalToolButton(
          icon: state.showHidden
              ? Icons.visibility
              : Icons.visibility_off_outlined,
          label: _t('hidden'),
          showLabel: false,
          color: context.colors.accent,
          selected: state.showHidden,
          onPressed: () => _run(() async {
            await manager.setShowHidden(!state.showHidden);
            await _persist('sftpHidden', state.showHidden);
          }),
        ),
        Builder(
          builder: (anchor) => TerminalToolButton(
            icon: Icons.settings_outlined,
            label: _t('columns'),
            showLabel: false,
            color: context.colors.accent,
            onPressed: () => _columns(anchor),
          ),
        ),
      ],
    ),
  );
  List<(String, String)> _breadcrumbs(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return [
      for (var i = 0; i < parts.length; i++)
        (parts[i], '/${parts.take(i + 1).join('/')}'),
    ];
  }

  Widget _table(
    List<SftpFileEntry> entries,
    Set<String> columns,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final visible = ['name', ..._optionalColumns.where(columns.contains)];
      const fixedWidths = {
        'size': 70.0,
        'modified': 88.0,
        'permissions': 80.0,
        'owner': 70.0,
        'group': 70.0,
      };
      final nameWidth = math.max(
        120.0,
        constraints.maxWidth -
            32 -
            visible
                .skip(1)
                .fold<double>(0, (sum, key) => sum + fixedWidths[key]!),
      );
      final widths = {'name': nameWidth, ...fixedWidths};
      final tableWidth =
          32 + visible.fold<double>(0, (sum, key) => sum + widths[key]!);
      final selected = session!.selectedNames;
      Widget check(bool? value, ValueChanged<bool?> change) => SizedBox(
        width: 32,
        height: 28,
        child: Transform.scale(
          scale: .78,
          child: Checkbox(
            value: value,
            tristate: true,
            onChanged: change,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: context.colors.softMuted),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.colors.canvas,
                    border: Border(
                      bottom: BorderSide(color: context.colors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      check(
                        entries.isEmpty || selected.isEmpty
                            ? false
                            : entries.every((e) => selected.contains(e.name))
                            ? true
                            : null,
                        (value) => session!.update(
                          selectedNames: value == true
                              ? entries.map((e) => e.name).toSet()
                              : <String>{},
                        ),
                      ),
                      for (final key in visible)
                        SizedBox(
                          width: widths[key],
                          child: InkWell(
                            onTap: () => setState(() {
                              _ascending = _sort == key ? !_ascending : true;
                              _sort = key;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _t(key),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: context.colors.muted,
                                      ),
                                    ),
                                  ),
                                  if (_sort == key)
                                    Icon(
                                      _ascending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      size: 12,
                                      color: context.colors.muted,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView.builder(
                      controller: _vertical,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isSelected = selected.contains(entry.name);
                        return Material(
                          color: isSelected
                              ? context.colors.accent.withValues(alpha: .12)
                              : context.colors.card,
                          child: InkWell(
                            onTap: () => _select(entry, entries),
                            onDoubleTap: () => _open(entry),
                            onSecondaryTapUp: (event) =>
                                _context(entry, event.globalPosition),
                            hoverColor: context.colors.chip,
                            child: Container(
                              height: math.max(
                                54,
                                MediaQuery.textScalerOf(context).scale(12) *
                                        3.2 +
                                    12,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: context.colors.border,
                                    width: .5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  check(
                                    isSelected,
                                    (_) =>
                                        _select(entry, entries, toggle: true),
                                  ),
                                  for (final key in visible)
                                    SizedBox(
                                      width: widths[key],
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                        ),
                                        child: key == 'name'
                                            ? Row(
                                                children: [
                                                  Image.asset(
                                                    'assets/terminal/icons/${entry.isDirectory
                                                        ? 'dir'
                                                        : entry.isLink
                                                        ? 'link'
                                                        : 'file'}.png',
                                                    width: 16,
                                                    height: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Tooltip(
                                                      message: entry.name,
                                                      waitDuration:
                                                          const Duration(
                                                            seconds: 1,
                                                          ),
                                                      child: Text(
                                                        entry.name,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: context
                                                              .colors
                                                              .accent,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (session!.favorites.any(
                                                    (f) =>
                                                        f.path ==
                                                        manager.entryPath(
                                                          session!,
                                                          entry,
                                                        ),
                                                  ))
                                                    Icon(
                                                      Icons.star,
                                                      size: 12,
                                                      color: context
                                                          .colors
                                                          .warning,
                                                    ),
                                                ],
                                              )
                                            : Text(
                                                switch (key) {
                                                  'size' => _size(entry.size),
                                                  'modified' =>
                                                    entry.modifyTime == null
                                                        ? '—'
                                                        : DateFormat(
                                                            'yyyy-MM-dd\nHH:mm:ss',
                                                          ).format(
                                                            entry.modifyTime!
                                                                .toLocal(),
                                                          ),
                                                  'permissions' =>
                                                    entry.permissions,
                                                  'owner' => entry.ownerName,
                                                  'group' => entry.groupName,
                                                  _ => '',
                                                },
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.6,
                                                  color: context.colors.text,
                                                ),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  static String _size(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _transferList() => Container(
    height: 190,
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.colors.border)),
    ),
    child: Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t('transfers'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: _transfers.clearFinished,
                child: Text(
                  _t('clearFinished'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              TerminalToolButton(
                icon: Icons.close,
                label: dt(context, 'close'),
                showLabel: false,
                onPressed: () => setState(() => _tasksVisible = false),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final task in _transfers.tasks.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            task.upload
                                ? Icons.upload_outlined
                                : Icons.download_outlined,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              task.name,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _t('transfer.${task.status.name}'),
                            style: TextStyle(
                              fontSize: 10,
                              color: task.status == SftpTransferStatus.error
                                  ? context.colors.danger
                                  : context.colors.muted,
                            ),
                          ),
                          TerminalToolButton(
                            icon: task.unfinished ? Icons.close : Icons.refresh,
                            label: task.unfinished
                                ? dt(context, 'cancel')
                                : dt(context, 'retry'),
                            showLabel: false,
                            onPressed: () => task.unfinished
                                ? _transfers.cancel(task)
                                : _transfers.retry(task),
                          ),
                        ],
                      ),
                      if (task.status == SftpTransferStatus.running)
                        LinearProgressIndicator(
                          value: task.total == null || task.total == 0
                              ? null
                              : (task.transferred / task.total!).clamp(0, 1),
                          minHeight: 2,
                        ),
                      Text(
                        task.error ??
                            '${_size(task.transferred)}${task.total == null ? '' : ' / ${_size(task.total)}'}${task.status == SftpTransferStatus.running ? ' · ${_size(task.speed.round())}/s' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: context.colors.muted,
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
