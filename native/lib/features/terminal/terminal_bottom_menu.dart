import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../features/servers/server_model.dart';
import '../../features/shell/sftp_tab.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/terminal_providers.dart';
import 'ssh_terminal_controller.dart';
import 'terminal_script_command.dart';
import 'terminal_script_library_sheet.dart';
import 'terminal_session.dart';
import 'terminal_session_manager.dart';

class TerminalBottomBar extends ConsumerStatefulWidget {
  const TerminalBottomBar({
    super.key,
    required this.manager,
    required this.active,
    required this.controller,
    required this.onInput,
    required this.showKeyPanel,
    required this.onToggleInput,
    required this.panelHeight,
    required this.keyboardVisible,
    this.onFocusTerminal,
  });

  final TerminalSessionManager manager;
  final TerminalSession? active;
  final SshTerminalController? controller;
  final ValueChanged<String> onInput;
  final bool showKeyPanel;
  final VoidCallback onToggleInput;
  final double panelHeight;
  final bool keyboardVisible;
  final VoidCallback? onFocusTerminal;

  @override
  ConsumerState<TerminalBottomBar> createState() => _TerminalBottomBarState();
}

class _TerminalBottomBarState extends ConsumerState<TerminalBottomBar> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            children: [
              _BarIcon(
                icon: Icons.edit_note_outlined,
                onTap: () => _showCommandInput(context),
              ),
              _BarIcon(
                icon: Icons.code_outlined,
                onTap: () => _showScripts(context),
              ),
              _BarIcon(
                icon: Icons.layers_outlined,
                onTap: () => _showConnections(context),
              ),
              _BarIcon(
                icon: Icons.folder_outlined,
                onTap: () => _showSftp(context),
              ),
              _BarIcon(
                icon: widget.keyboardVisible
                    ? Icons.more_horiz
                    : Icons.keyboard_outlined,
                onTap: widget.onToggleInput,
              ),
            ],
          ),
        ),
        if (widget.showKeyPanel)
          SizedBox(
            height: widget.panelHeight,
            child: _ShortcutKeyPanel(
              controller: widget.controller,
              onInput: widget.onInput,
            ),
          ),
      ],
    );
  }

  Future<void> _showCommandInput(BuildContext context) async {
    final session = ref.read(terminalSessionManagerProvider).activeSession;
    if (session == null) return;
    final l = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppPalette.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_outlined,
                      color: AppPalette.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l.tr('terminal.menu.commandInput'),
                    style: const TextStyle(
                      color: AppPalette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 8,
                minLines: 4,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: AppPalette.text,
                  height: 1.5,
                ),
                cursorColor: AppPalette.accent,
                decoration: InputDecoration(
                  hintText: l.tr('terminal.commandInput.hint'),
                  hintStyle: const TextStyle(color: AppPalette.softMuted),
                  filled: true,
                  fillColor: AppPalette.canvas,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppPalette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppPalette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppPalette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.muted,
                    ),
                    child: Text(l.tr('common.cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                    icon: const Icon(Icons.send, size: 16),
                    label: Text(l.tr('terminal.commandInput.send')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.primary,
                      foregroundColor: AppPalette.fontOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    widget.onInput(result);
  }

  Future<void> _showScripts(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => TerminalScriptLibrarySheet(
        onSend: (command, useBase64) =>
            _sendScript(context, command, useBase64),
      ),
    );
  }

  bool _sendScript(BuildContext context, String command, bool useBase64) {
    final l = AppLocalizations.of(context);
    final session = ref.read(terminalSessionManagerProvider).activeSession;
    if (session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.tr('terminal.script.noActive'))));
      return false;
    }
    session.controller.writeInput(
      formatTerminalScriptCommand(command, useBase64: useBase64),
    );
    return true;
  }

  Future<void> _showConnections(BuildContext context) async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _TerminalSheetFrame(
          title: l.tr('terminal.menu.connections'),
          icon: Icons.layers_outlined,
          child: _ConnectionsSheet(manager: widget.manager),
        ),
      ),
    );
    widget.onFocusTerminal?.call();
  }

  Future<void> _showSftp(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.90,
        child: _TerminalSheetFrame(
          title: l.tr('terminal.menu.sftp'),
          icon: Icons.folder_outlined,
          child: SftpPanel(
            initialHostId: ref
                .read(terminalSessionManagerProvider)
                .activeSession
                ?.config
                .hostId,
            allowDisconnect: false,
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: active
              ? BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Icon(
            icon,
            size: 21,
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

const _kKeyStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
const _kKeyHeight = 36.0;
const _kRowGap = 4.0;
const _kSectionGap = 10.0;

class _ShortcutKeyPanel extends StatelessWidget {
  const _ShortcutKeyPanel({
    required this.controller,
    required this.onInput,
  });

  final SshTerminalController? controller;
  final ValueChanged<String> onInput;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ctrlNotifier = controller?.ctrlPending;
    final l = AppLocalizations.of(context);
    return Container(
      color: colors.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Modifiers
          _buildRow([
            _KeyBtn('Esc', () => onInput('\x1b')),
            _KeyBtn('Tab', () => onInput('\t')),
            if (ctrlNotifier != null)
              _ToggleKeyBtn('Ctrl', ctrlNotifier, controller!.toggleCtrl)
            else
              _KeyBtn('Ctrl', () {}),
            _KeyBtn('Alt', () => onInput('\x1b')),
            _KeyBtn('Home', () => onInput('\x1b[H')),
            _KeyBtn('End', () => onInput('\x1b[F')),
            _KeyBtn('Ins', () => onInput('\x1b[2~')),
            _KeyBtn('Del', () => onInput('\x1b[3~')),
          ]),
          const SizedBox(height: _kRowGap),
          // Arrows & navigation
          _buildRow([
            _KeyBtn('←', () => onInput('\x1b[D')),
            _KeyBtn('↑', () => onInput('\x1b[A')),
            _KeyBtn('↓', () => onInput('\x1b[B')),
            _KeyBtn('→', () => onInput('\x1b[C')),
            _KeyBtn('PgUp', () => onInput('\x1b[5~')),
            _KeyBtn('PgDn', () => onInput('\x1b[6~')),
          ]),
          const SizedBox(height: _kSectionGap),
          // Common Ctrl combinations
          _buildRow([
            _HintKeyBtn('^C', () => onInput('\x03'), l.tr('terminal.hint.ctrlC')),
            _HintKeyBtn('^Z', () => onInput('\x1a'), l.tr('terminal.hint.ctrlZ')),
            _HintKeyBtn('^D', () => onInput('\x04'), l.tr('terminal.hint.ctrlD')),
            _HintKeyBtn('^L', () => onInput('\x0c'), l.tr('terminal.hint.ctrlL')),
            _HintKeyBtn('^U', () => onInput('\x15'), l.tr('terminal.hint.ctrlU')),
            _HintKeyBtn('^K', () => onInput('\x0b'), l.tr('terminal.hint.ctrlK')),
          ]),
          const SizedBox(height: _kRowGap),
          _buildRow([
            _HintKeyBtn('^A', () => onInput('\x01'), l.tr('terminal.hint.ctrlA')),
            _HintKeyBtn('^E', () => onInput('\x05'), l.tr('terminal.hint.ctrlE')),
            _HintKeyBtn('^W', () => onInput('\x17'), l.tr('terminal.hint.ctrlW')),
            _HintKeyBtn('^Y', () => onInput('\x19'), l.tr('terminal.hint.ctrlY')),
            _HintKeyBtn('^X', () => onInput('\x18'), l.tr('terminal.hint.ctrlX')),
            _HintKeyBtn('^R', () => onInput('\x12'), l.tr('terminal.hint.ctrlR')),
          ]),
          const SizedBox(height: _kRowGap),
          // Vim shortcuts
          _buildRow([
            _HintKeyBtn(':w', () => onInput(':w\n'), l.tr('terminal.hint.vimW')),
            _HintKeyBtn(':q', () => onInput(':q\n'), l.tr('terminal.hint.vimQ')),
            _HintKeyBtn(':wq', () => onInput(':wq\n'), l.tr('terminal.hint.vimWQ')),
            _HintKeyBtn(':q!', () => onInput(':q!\n'), l.tr('terminal.hint.vimQF')),
            _HintKeyBtn('dd', () => onInput('dd'), l.tr('terminal.hint.vimDD')),
            _HintKeyBtn('yy', () => onInput('yy'), l.tr('terminal.hint.vimYY')),
          ]),
          const SizedBox(height: _kSectionGap),
          // F1–F6
          _buildRow([
            _KeyBtn('F1', () => onInput('\x1bOP')),
            _KeyBtn('F2', () => onInput('\x1bOQ')),
            _KeyBtn('F3', () => onInput('\x1bOR')),
            _KeyBtn('F4', () => onInput('\x1bOS')),
            _KeyBtn('F5', () => onInput('\x1b[15~')),
            _KeyBtn('F6', () => onInput('\x1b[17~')),
          ]),
          const SizedBox(height: _kRowGap),
          // F7–F12
          _buildRow([
            _KeyBtn('F7', () => onInput('\x1b[18~')),
            _KeyBtn('F8', () => onInput('\x1b[19~')),
            _KeyBtn('F9', () => onInput('\x1b[20~')),
            _KeyBtn('F10', () => onInput('\x1b[21~')),
            _KeyBtn('F11', () => onInput('\x1b[23~')),
            _KeyBtn('F12', () => onInput('\x1b[24~')),
          ]),
          const SizedBox(height: _kSectionGap),
          // Symbols
          _buildRow('! @ # \$ % ^ & *'.split(' ').map(
            (c) => _KeyBtn(c, () => onInput(c)) as Widget,
          ).toList()),
          const SizedBox(height: _kRowGap),
          _buildRow('~ ` ( ) _ - + ='.split(' ').map(
            (c) => _KeyBtn(c, () => onInput(c)) as Widget,
          ).toList()),
          const SizedBox(height: _kRowGap),
          _buildRow('[ ] { } \\ | ; :'.split(' ').map(
            (c) => _KeyBtn(c, () => onInput(c)) as Widget,
          ).toList()),
          const SizedBox(height: _kRowGap),
          _buildRow('\' " , . < > / ?'.split(' ').map(
            (c) => _KeyBtn(c, () => onInput(c)) as Widget,
          ).toList()),
        ],
      ),
    );
  }

  static Widget _buildRow(List<Widget> children) {
    return Row(
      children: [
        for (final child in children)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: child,
            ),
          ),
      ],
    );
  }
}

class _KeyBtn extends StatelessWidget {
  const _KeyBtn(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          height: _kKeyHeight,
          child: Center(
            child: Text(
              label,
              style: _kKeyStyle.copyWith(color: colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintKeyBtn extends StatelessWidget {
  const _HintKeyBtn(this.label, this.onTap, this.hint);

  final String label;
  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        onLongPress: () {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('$label  $hint'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
        },
        child: SizedBox(
          height: _kKeyHeight,
          child: Center(
            child: Text(
              label,
              style: _kKeyStyle.copyWith(color: colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleKeyBtn extends StatelessWidget {
  const _ToggleKeyBtn(this.label, this.notifier, this.onTap);

  final String label;
  final ValueNotifier<bool> notifier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, active, _) => Material(
        color: active ? colors.primaryContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: _kKeyHeight,
            child: Center(
              child: Text(
                label,
                style: _kKeyStyle.copyWith(
                  color: active ? colors.primary : colors.onSurface,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet contents (unchanged)
// ---------------------------------------------------------------------------

class _ConnectionsSheet extends ConsumerStatefulWidget {
  const _ConnectionsSheet({required this.manager});

  final TerminalSessionManager manager;

  @override
  ConsumerState<_ConnectionsSheet> createState() => _ConnectionsSheetState();
}

class _ConnectionsSheetState extends ConsumerState<_ConnectionsSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _connectingId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect(ServerModel server) async {
    final l = AppLocalizations.of(context);
    if (server.isWindows) {
      _showSnack(l.tr('servers.windowsUnsupported'));
      return;
    }
    if (!server.canConnect) {
      _showSnack(l.tr('servers.notConfigured'));
      return;
    }
    setState(() => _connectingId = server.id);
    try {
      final config = await ref
          .read(serverRepositoryProvider)
          .fetchSshConfig(server.id);
      await ref.read(terminalSessionManagerProvider).openSession(config);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      _showSnack(l.trf('terminal.openFailed', [error.toString()]));
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostListProvider);
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: l.tr('servers.searchHint'),
                    prefixIcon: const Icon(Icons.search, size: 19),
                    isDense: true,
                    filled: true,
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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => _MessageList(
                  message: l.trf(
                    'terminal.loadServersFailed',
                    [error.toString()],
                  ),
                  action: TextButton(
                    onPressed: () =>
                        ref.read(hostListProvider.notifier).refresh(),
                    child: Text(l.tr('common.retry')),
                  ),
                ),
                data: (servers) =>
                    _buildList(context, servers, colors, l),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    List<ServerModel> servers,
    ColorScheme colors,
    AppLocalizations l,
  ) {
    final sessions = widget.manager.sessions.toList(growable: false);

    final disconnectedServers = servers.where((server) {
      if (_query.isEmpty) return true;
      final haystack = [
        server.displayName,
        server.host,
        server.username,
        server.group,
        ...server.tag,
      ].join(' ').toLowerCase();
      return haystack.contains(_query);
    }).toList(growable: false);

    if (sessions.isEmpty && disconnectedServers.isEmpty) {
      return _MessageList(message: l.tr('servers.emptyFiltered'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (sessions.isNotEmpty) ...[
          _SectionLabel(l.tr('terminal.connections.connected')),
          for (final session in sessions) ...[
            _ConnectedRow(
              session: session,
              active: session.id == widget.manager.activeId,
              onSelect: () {
                widget.manager.setActive(session.id);
                Navigator.of(context).pop();
              },
              onReconnect: () async {
                widget.manager.reconnect(session.id);
                widget.manager.setActive(session.id);
                Navigator.of(context).pop();
              },
              onClose: () => widget.manager.closeSession(session.id),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (disconnectedServers.isNotEmpty) ...[
          _SectionLabel(l.tr('terminal.connections.disconnected')),
          for (final server in disconnectedServers) ...[
            _DisconnectedRow(
              server: server,
              connecting: _connectingId == server.id,
              onTap: _connectingId == null
                  ? () => _connect(server)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  const _ConnectedRow({
    required this.session,
    required this.active,
    required this.onSelect,
    required this.onReconnect,
    required this.onClose,
  });

  final TerminalSession session;
  final bool active;
  final VoidCallback onSelect;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: active ? colors.primaryContainer : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              _StatusDot(status: session.status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _statusText(l, session.status),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (active)
                const Icon(Icons.check_rounded),
              IconButton(
                tooltip: l.tr('terminal.reconnect'),
                onPressed: () => onReconnect(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
              IconButton(
                tooltip: l.tr('terminal.closeTerminal'),
                onPressed: () => onClose(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedRow extends StatelessWidget {
  const _DisconnectedRow({
    required this.server,
    required this.connecting,
    required this.onTap,
  });

  final ServerModel server;
  final bool connecting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = server.isWindows || !server.canConnect;
    final textColor = disabled ? colors.outline : colors.onSurface;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, color: textColor),
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
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server.connectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: disabled
                            ? colors.outline
                            : colors.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (connecting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  disabled
                      ? Icons.block_outlined
                      : Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: disabled ? colors.outline : colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalSheetFrame extends StatelessWidget {
  const _TerminalSheetFrame({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              child: Row(
                children: [
                  Icon(icon, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).tr('common.close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 24),
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        if (action != null) ...[
          const SizedBox(height: 8),
          Center(child: action),
        ],
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final TerminalSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TerminalSessionStatus.connecting => Colors.amber,
      TerminalSessionStatus.connected => Colors.green,
      TerminalSessionStatus.disconnected => Colors.grey,
      TerminalSessionStatus.error => Theme.of(context).colorScheme.error,
    };
    return Icon(Icons.circle, size: 10, color: color);
  }
}

String _statusText(AppLocalizations l, TerminalSessionStatus status) {
  return switch (status) {
    TerminalSessionStatus.connecting => l.tr('terminal.status.connecting'),
    TerminalSessionStatus.connected => l.tr('terminal.status.connected'),
    TerminalSessionStatus.disconnected => l.tr('terminal.status.disconnected'),
    TerminalSessionStatus.error => l.tr('terminal.status.error'),
  };
}
