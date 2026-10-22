import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../l10n/app_localizations.dart';
import 'desktop_code_editor.dart';
import 'desktop_terminal_settings.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../state/auth_notifier.dart';
import '../../../state/plus_info_notifier.dart';
import '../../../state/storage_providers.dart';
import '../../docker/docker_container.dart';
import '../../docker/docker_session_manager.dart';
import '../../servers/server_model.dart';
import 'terminal_widgets.dart';

/// Desktop view; shares the existing Docker protocol/session service.
class DesktopDockerPanel extends ConsumerStatefulWidget {
  const DesktopDockerPanel({
    super.key,
    required this.server,
    required this.manager,
    required this.onExecCommand,
  });
  final ServerModel server;
  final DockerSessionManager manager;
  final ValueChanged<String> onExecCommand;
  @override
  ConsumerState<DesktopDockerPanel> createState() => _DesktopDockerPanelState();
}

class _DesktopDockerPanelState extends ConsumerState<DesktopDockerPanel> {
  final _selected = <String>{};
  String? _hovered;
  bool _batch = false;
  int _progress = 0, _total = 0;
  String _batchAction = '';
  Timer? _timer;
  bool _connecting = false;
  String? _error;
  DockerSessionState? get session =>
      widget.manager.sessionFor(widget.server.id);
  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(isPlusActiveProvider, (_, active) {
      if (active) unawaited(_connect());
    });
    Future.microtask(_connect);
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      final state = session;
      if (!_batch &&
          _selected.isEmpty &&
          state?.status == DockerConnectionStatus.connected &&
          !state!.loading &&
          state.operatingIds.isEmpty) {
        state.client.refresh();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    if (widget.manager.isConnected(widget.server.id)) return;
    if (!ref.read(isPlusActiveProvider)) return;
    final auth = ref.read(authProvider).session;
    if (auth == null) return;
    setState(() => _connecting = true);
    try {
      await widget.manager.connect(
        server: widget.server,
        authSession: auth,
        cookieStore: ref.read(cookieStoreProvider),
        certificateTrust: ref.read(certificateTrustProvider),
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<bool> _confirm(
    String command,
    List<DockerContainer> containers,
  ) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (context) => DesktopManagementDialog(
          title: dt(context, 'docker.$command'),
          width: 480,
          body: Text(containers.map((c) => c.name).join(', ')),
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
  Future<void> _operate(
    String command,
    List<DockerContainer> containers, {
    bool batch = false,
  }) async {
    if (_batch) return;
    final eligible = containers
        .where(
          (c) => switch (command) {
            'start' => !c.isRunning,
            'stop' || 'restart' => c.isRunning,
            _ => true,
          },
        )
        .toList();
    if (eligible.isEmpty) {
      terminalNotice(context, dt(context, 'docker.noEligible'));
      return;
    }
    if ((batch || command == 'delete') && !await _confirm(command, eligible)) {
      return;
    }
    if (!mounted) return;
    if (!batch) {
      _send(command, eligible.single);
      return;
    }
    setState(() {
      _batch = true;
      _progress = 0;
      _total = eligible.length;
      _batchAction = command;
    });
    final failures = <String>[];
    for (final container in eligible) {
      if (!mounted) break;
      setState(() => _progress++);
      final state = session;
      try {
        if (state?.status != DockerConnectionStatus.connected) {
          throw StateError(dt(context, 'docker.connectFailed'));
        }
        // Subscribe before sending. Web's protocol returns one result per operation.
        final result = state!.client.operationStream.first.timeout(
          const Duration(seconds: 30),
        );
        _send(command, container);
        final completed = await result;
        if (!completed.success) {
          failures.add('${container.name}: ${completed.message}');
        }
      } catch (error) {
        failures.add('${container.name}: $error');
      }
      state?.operatingIds.remove(container.id);
    }
    if (!mounted) return;
    setState(() {
      _batch = false;
      _selected.clear();
    });
    widget.manager.refresh(widget.server.id);
    terminalNotice(
      context,
      '${dt(context, 'docker.batchDone')} ${_total - failures.length}/$_total${failures.isEmpty ? '' : '\n${failures.join('\n')}'}',
    );
  }

  void _send(String command, DockerContainer container) {
    final manager = widget.manager;
    switch (command) {
      case 'start':
        manager.start(container, hostId: widget.server.id);
      case 'stop':
        manager.stop(container, hostId: widget.server.id);
      case 'restart':
        manager.restart(container, hostId: widget.server.id);
      case 'delete':
        manager.delete(container, hostId: widget.server.id);
    }
  }

  Future<void> _logs(DockerContainer container) => showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    closeOnPressEscape: false,
    builder: (_) => _DesktopDockerLogs(
      manager: widget.manager,
      hostId: widget.server.id,
      container: container,
    ),
  );
  Future<void> _openPort(String port) async {
    final match = RegExp(r':(\d+)->').firstMatch(port);
    if (match == null) return;
    final url = Uri(
      scheme: 'http',
      host: widget.server.host,
      port: int.parse(match.group(1)!),
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) terminalNotice(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final plus = ref.watch(isPlusActiveProvider);
    if (!plus) return Center(child: Text(dt(context, 'plusRequired')));
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) {
        final state = session;
        if (_connecting ||
            state?.status == DockerConnectionStatus.connecting ||
            state?.loading == true && state?.containers.isEmpty != false) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state == null || state.status != DockerConnectionStatus.connected) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ??
                      state?.errorMessage ??
                      dt(context, 'docker.connectFailed'),
                ),
                TextButton(
                  onPressed: _connect,
                  child: Text(dt(context, 'retry')),
                ),
              ],
            ),
          );
        }
        final all = state.containers;
        _selected.removeWhere((id) => !all.any((c) => c.id == id));
        final list = all;
        final selection = all.where((c) => _selected.contains(c.id)).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  spacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 24,
                          child: Checkbox(
                            value:
                                list.isNotEmpty &&
                                    list.every((c) => _selected.contains(c.id))
                                ? true
                                : _selected.isEmpty
                                ? false
                                : null,
                            tristate: true,
                            onChanged: _batch
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      _selected.addAll(list.map((c) => c.id));
                                    } else {
                                      _selected.clear();
                                    }
                                  }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context).tr('docker.selectAll'),
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (_selected.isNotEmpty || _batch)
                          Container(
                            margin: const EdgeInsets.only(left: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.accentSoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _batch
                                  ? '${dt(context, 'docker.$_batchAction')} $_progress/$_total'
                                  : AppLocalizations.of(context).trf(
                                      'docker.selectedCount',
                                      ['${_selected.length}'],
                                    ),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selection.isNotEmpty) ...[
                          for (final action in [
                            'start',
                            'restart',
                            'stop',
                            'delete',
                          ])
                            SizedBox(
                              height: 26,
                              child: OutlinedButton(
                                onPressed:
                                    _batch || state.operatingIds.isNotEmpty
                                    ? null
                                    : () => _operate(
                                        action,
                                        selection,
                                        batch: true,
                                      ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _color(action),
                                  backgroundColor: _color(
                                    action,
                                  ).withValues(alpha: .08),
                                  side: BorderSide(
                                    color: _color(
                                      action,
                                    ).withValues(alpha: .35),
                                  ),
                                  minimumSize: const Size(0, 26),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                  ),
                                  shape: const RoundedRectangleBorder(),
                                ),
                                child: Text(
                                  dt(
                                    context,
                                    action == 'start'
                                        ? 'docker.batchStart'
                                        : 'docker.$action',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          const SizedBox(width: 10),
                        ],
                        SizedBox(
                          height: 26,
                          child: FilledButton.icon(
                            onPressed: _batch
                                ? null
                                : () =>
                                      widget.manager.refresh(widget.server.id),
                            style: desktopButtonStyle(context, primary: true)
                                .copyWith(
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size(0, 26),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 9),
                                  ),
                                ),
                            icon: const TerminalIcon(
                              Icons.restart_alt,
                              size: 12,
                            ),
                            label: Text(
                              dt(context, 'sftp.refresh'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(fontSize: 12, color: context.colors.danger),
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(dt(context, 'docker.noContainers')))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1350
                            ? 4
                            : constraints.maxWidth >= 990
                            ? 3
                            : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: (list.length / columns).ceil(),
                          itemBuilder: (context, row) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var col = 0; col < columns; col++)
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: col == columns - 1 ? 0 : 12,
                                      ),
                                      child: row * columns + col < list.length
                                          ? _card(
                                              list[row * columns + col],
                                              state,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Color _color(String action) => switch (action) {
    'start' => context.colors.success,
    'restart' => context.colors.accent,
    'stop' => context.colors.warning,
    'delete' => context.colors.danger,
    _ => context.colors.muted,
  };
  Color _statusColor(String status) => switch (status) {
    'running' => context.colors.success,
    'paused' => context.colors.warning,
    'exited' || 'dead' => context.colors.danger,
    _ => context.colors.muted,
  };
  Widget _circleAction(
    String action,
    DockerContainer container,
    bool operating,
  ) {
    final enabled =
        !operating &&
        !(action == 'start' && container.isRunning) &&
        !(['stop', 'restart'].contains(action) && !container.isRunning);
    return Tooltip(
      message: dt(context, 'docker.$action'),
      child: SizedBox(
        width: 28,
        height: 28,
        child: OutlinedButton(
          onPressed: enabled
              ? () {
                  if (action == 'logs') {
                    _logs(container);
                  } else {
                    _operate(action, [container]);
                  }
                }
              : null,
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            minimumSize: const Size(28, 28),
            foregroundColor: _color(action),
            backgroundColor: _color(action).withValues(alpha: .08),
            side: BorderSide(
              color: (enabled ? _color(action) : context.colors.border)
                  .withValues(alpha: .5),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: TerminalIcon(
            action == 'logs' ? Icons.article_outlined : _icon(action),
            size: 14,
          ),
        ),
      ),
    );
  }

  IconData _icon(String action) => switch (action) {
    'start' => Icons.play_arrow_outlined,
    'restart' => Icons.restart_alt,
    'stop' => Icons.stop_outlined,
    _ => Icons.delete_outline,
  };
  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 45,
          child: Text(
            '$label:',
            style: TextStyle(fontSize: 13, color: context.colors.muted),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: value,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.colors.text),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card(DockerContainer container, DockerSessionState state) {
    final operating = state.operatingIds.contains(container.id);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = container.id),
      onExit: (_) => setState(() => _hovered = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.card,
          boxShadow: _hovered == container.id
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .13),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
          border: Border.all(
            color: _selected.contains(container.id)
                ? context.colors.accent
                : context.colors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Transform.rotate(
                    angle: -.26,
                    child: TerminalIcon(
                      Icons.layers_outlined,
                      size: 80,
                      color: context.colors.muted.withValues(alpha: .15),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 25,
                      height: 25,
                      child: Checkbox(
                        value: _selected.contains(container.id),
                        onChanged: (_) => setState(() {
                          if (!_selected.add(container.id)) {
                            _selected.remove(container.id);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Tooltip(
                        message: dt(context, 'docker.exec'),
                        child: InkWell(
                          onTap: !container.isRunning || _batch
                              ? null
                              : () => widget.onExecCommand(
                                  'docker exec -it ${container.id} sh',
                                ),
                          child: Text(
                            container.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(container.status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        container.status,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: context.colors.border),
                ),
                _info('ID', container.shortId),
                _info(dt(context, 'docker.image'), container.image),
                _info(
                  dt(context, 'docker.uptime'),
                  container.uptime.isEmpty ? '—' : container.uptime,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${dt(context, 'docker.ports')}:',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (container.ports.isEmpty)
                            const Text('—', style: TextStyle(fontSize: 13)),
                          for (final port in container.ports)
                            Tooltip(
                              message: port,
                              child: SizedBox(
                                height: 20,
                                child: TextButton(
                                  onPressed: port.contains('->')
                                      ? () => _openPort(port)
                                      : null,
                                  style: TextButton.styleFrom(
                                    foregroundColor: context.colors.accent,
                                    backgroundColor: context.colors.accentSoft,
                                    minimumSize: const Size(0, 20),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  child: Text(
                                    port,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: context.colors.border.withValues(alpha: .65),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final action in [
                      'start',
                      'restart',
                      'stop',
                      'delete',
                      'logs',
                    ])
                      Expanded(
                        child: Center(
                          child: _circleAction(
                            action,
                            container,
                            operating || _batch,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDockerLogs extends ConsumerStatefulWidget {
  const _DesktopDockerLogs({
    required this.manager,
    required this.hostId,
    required this.container,
  });
  final DockerSessionManager manager;
  final String hostId;
  final DockerContainer container;
  @override
  ConsumerState<_DesktopDockerLogs> createState() => _DesktopDockerLogsState();
}

class _DesktopDockerLogsState extends ConsumerState<_DesktopDockerLogs> {
  Timer? _timer;
  final _code = CodeLineEditingController.fromText('');
  bool _follow = true;
  DateTime? _updated;
  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_onLogs);
    Future.microtask(() {
      if (mounted) {
        widget.manager.getLogs(widget.container, hostId: widget.hostId);
      }
    });
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) =>
          widget.manager.refreshLogs(widget.container, hostId: widget.hostId),
    );
  }

  void _onLogs() {
    final logs = widget.manager.sessionFor(widget.hostId)?.logs ?? '';
    if (_code.text != logs) {
      _code.text = logs;
      if (mounted) setState(() => _updated = DateTime.now());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.manager.removeListener(_onLogs);
    _code.dispose();
    super.dispose();
  }

  void _pref(String key, Object value) =>
      ref.read(desktopTerminalPreferencesProvider.notifier).set(key, value);
  @override
  Widget build(BuildContext context) {
    final pref = ref.watch(desktopTerminalPreferencesProvider);
    final wrap = pref['dockerLogWrap'] != false,
        minimap = pref['dockerLogMinimap'] != false;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: MediaQuery.sizeOf(context).height * .03,
      ),
      backgroundColor: context.colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * .68,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.container.name,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  TerminalToolButton(
                    icon: Icons.close,
                    label: dt(context, 'close'),
                    showLabel: false,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  EditorSwitch(
                    label: dt(context, 'editor.wrap'),
                    value: wrap,
                    onChanged: (v) => _pref('dockerLogWrap', v),
                  ),
                  EditorSwitch(
                    label: dt(context, 'editor.minimap'),
                    value: minimap,
                    onChanged: (v) => _pref('dockerLogMinimap', v),
                  ),
                  EditorSwitch(
                    label: dt(context, 'docker.autoScroll'),
                    value: _follow,
                    onChanged: (v) => setState(() => _follow = v),
                  ),
                  TerminalMenuButton(
                    label: dt(context, 'docker.manualRefresh'),
                    outlined: true,
                    onPressed: () => widget.manager.refreshLogs(
                      widget.container,
                      hostId: widget.hostId,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  DesktopCodeEditor(
                    controller: _code,
                    language: CodeHighlightThemeMode(mode: langBash),
                    theme: Theme.of(context).brightness == Brightness.dark
                        ? 'dark'
                        : 'light',
                    fontSize: 13,
                    readOnly: true,
                    wordWrap: wrap,
                    minimap: minimap,
                    follow: _follow,
                  ),
                  if (_code.text.isEmpty)
                    Center(
                      child: Text(
                        dt(context, 'docker.noLogs'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${dt(context, 'docker.lines')}: ${_code.lineCount}    ${dt(context, 'docker.size')}: ${desktopEditorSize(utf8.encode(_code.text).length)}${_updated == null ? '' : '    ${dt(context, 'docker.updated')}: ${_updated!.toLocal().toString().substring(11, 19)}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    style: desktopButtonStyle(context),
                    onPressed: () => Navigator.pop(context),
                    child: Text(dt(context, 'close')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
