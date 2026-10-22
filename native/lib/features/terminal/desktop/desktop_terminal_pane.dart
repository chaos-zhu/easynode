import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import '../../../core/ui/app_color_theme.dart';
import 'desktop_terminal_settings.dart';
import 'desktop_terminal_workspace.dart';
import 'terminal_search.dart';
import 'terminal_context_menu.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../state/plus_info_notifier.dart';
import 'terminal_widgets.dart';

class DesktopTerminalPaneView extends ConsumerStatefulWidget {
  const DesktopTerminalPaneView({
    super.key,
    required this.pane,
    required this.workspace,
    required this.onFocus,
    required this.onAi,
    required this.onSyncPath,
    required this.onClose,
    required this.onFullscreen,
    this.onExitFullscreen,
    this.sftpVisible = false,
  });
  final DesktopTerminalPane pane;
  final DesktopTerminalWorkspace workspace;
  final VoidCallback onFocus;
  final ValueChanged<String> onAi;
  final ValueChanged<String> onSyncPath;
  final VoidCallback onClose;
  final VoidCallback onFullscreen;
  final VoidCallback? onExitFullscreen;
  final bool sftpVisible;
  @override
  ConsumerState<DesktopTerminalPaneView> createState() =>
      _DesktopTerminalPaneViewState();
}

class _DesktopTerminalPaneViewState
    extends ConsumerState<DesktopTerminalPaneView> {
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false,
      _caseSensitive = false,
      _wholeWord = false,
      _regex = false;
  List<TerminalSearchMatch> _matches = [];
  final List<TerminalHighlight> _highlights = [];
  int _current = 0;
  double _fontDelta = 0;
  String? _searchError;
  String _lastSelection = '';
  bool _primarySelection = false;
  Timer? _searchTimer;
  DesktopTerminalPane get pane => widget.pane;

  @override
  void initState() {
    super.initState();
    pane.terminal.addListener(_onOutput);
    _searchFocus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void _onOutput() {
    if (!_searchOpen || _query.text.isEmpty) return;
    _searchTimer ??= Timer(const Duration(milliseconds: 180), () {
      _searchTimer = null;
      if (mounted) _search();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    pane.terminal.removeListener(_onOutput);
    _clearHighlights();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get selected {
    final range = pane.viewController.selection;
    return range == null ? '' : pane.terminal.buffer.getText(range);
  }

  void _copy() {
    if (selected.isNotEmpty) Clipboard.setData(ClipboardData(text: selected));
  }

  Future<void> _paste() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || pane.closed || text == null) return;
      pane.terminal.paste(text);
      pane.focusNode.requestFocus();
    } catch (error) {
      if (mounted) terminalNotice(context, error.toString());
    }
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    if (selected.isNotEmpty) _query.text = selected;
    _search();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _clearHighlights();
    setState(() => _searchOpen = false);
    pane.focusNode.requestFocus();
  }

  void _clearHighlights() {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
  }

  void _search() {
    _clearHighlights();
    try {
      _matches = searchTerminal(
        pane.terminal,
        _query.text,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
        regex: _regex,
      );
      _searchError = null;
      if (_current >= _matches.length) _current = 0;
      _applyHighlight(scroll: false);
    } on FormatException {
      _matches = [];
      _searchError = dt(context, 'invalidRegex');
    }
    if (mounted) setState(() {});
  }

  void _applyHighlight({bool scroll = true}) {
    _clearHighlights();
    final buffer = pane.terminal.buffer;
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      _highlights.add(
        pane.viewController.highlight(
          p1: buffer.createAnchor(match.start.x, match.start.y),
          p2: buffer.createAnchor(match.end.x, match.end.y),
          color: i == _current
              ? Colors.orange.withValues(alpha: .65)
              : Colors.yellow.withValues(alpha: .25),
        ),
      );
    }
    if (scroll &&
        _matches.isNotEmpty &&
        pane.scrollController.hasClients &&
        pane.viewKey.currentState != null) {
      final target =
          (_matches[_current].start.y *
                  pane.viewKey.currentState!.renderTerminal.lineHeight)
              .clamp(0.0, pane.scrollController.position.maxScrollExtent);
      pane.scrollController.jumpTo(target);
    }
  }

  void _next(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _current = (_current + delta) % _matches.length);
    _applyHighlight();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      widget.onFullscreen();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        widget.onExitFullscreen != null) {
      widget.onExitFullscreen!();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed;
    final controlShift = keyboard.isControlPressed && keyboard.isShiftPressed;
    if ((command || controlShift) &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    if ((command || controlShift) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    if ((command || controlShift) &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (command && event.logicalKey == LogicalKeyboardKey.keyW) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if ((command || keyboard.isControlPressed) &&
        [
          LogicalKeyboardKey.equal,
          LogicalKeyboardKey.minus,
          LogicalKeyboardKey.digit0,
        ].contains(event.logicalKey)) {
      setState(
        () => _fontDelta = event.logicalKey == LogicalKeyboardKey.digit0
            ? 0
            : (_fontDelta +
                      (event.logicalKey == LogicalKeyboardKey.equal ? 1 : -1))
                  .clamp(-10, 14),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _contextMenu(Offset position) async {
    widget.onFocus();
    final text = selected;
    final trimmed = text.trim();
    final connected = pane.status == DesktopTerminalStatus.connected;
    final plus = ref.read(isPlusActiveProvider);
    final dockerId = RegExp(r'^[a-f0-9]{12,64}$').hasMatch(trimmed);
    final composeFile = RegExp(
      r'^(?:.*/)?(?:docker-)?compose\.(?:yml|yaml)$',
    ).hasMatch(trimmed);
    final choice = await showTerminalContextMenu(context, [
      if (trimmed.isNotEmpty)
        TerminalMenuAction(
          'ai',
          dt(context, 'sendAi'),
          Icons.chat_bubble_outline,
        ),
      if (text.isNotEmpty)
        TerminalMenuAction('copy', dt(context, 'copy'), Icons.copy_outlined),
      TerminalMenuAction(
        'paste',
        dt(context, 'paste'),
        Icons.content_paste,
        enabled: connected,
      ),
      if (text.isNotEmpty)
        TerminalMenuAction(
          'selection',
          dt(context, 'pasteSelection'),
          Icons.input,
          enabled: connected,
        ),
      TerminalMenuAction('find', dt(context, 'find'), Icons.search),
      TerminalMenuAction(
        'clear',
        dt(context, 'clear'),
        Icons.layers_clear_outlined,
      ),
      TerminalMenuAction('reconnect', dt(context, 'reconnect'), Icons.refresh),
      if (widget.sftpVisible)
        TerminalMenuAction(
          'path',
          dt(context, 'syncPath'),
          Icons.folder_open_outlined,
          enabled: connected,
        ),
      if (dockerId)
        TerminalMenuAction(
          'docker',
          dt(context, 'docker.detected'),
          Icons.layers_outlined,
          children: [
            TerminalMenuAction(
              'hint',
              dt(context, plus ? 'docker.detected' : 'plusRequired'),
              Icons.info_outline,
              enabled: false,
            ),
            for (final action in ['Shell', 'Stop', 'Restart', 'Remove', 'Logs'])
              TerminalMenuAction(
                'docker$action',
                dt(context, 'docker$action'),
                Icons.layers_outlined,
                enabled: plus && connected,
                danger: action == 'Remove',
              ),
          ],
        ),
      if (composeFile)
        TerminalMenuAction(
          'compose',
          dt(context, 'compose.detected'),
          Icons.layers_outlined,
          children: [
            TerminalMenuAction(
              'hint',
              dt(context, plus ? 'compose.detected' : 'plusRequired'),
              Icons.info_outline,
              enabled: false,
            ),
            for (final action in [
              'up',
              'down',
              'restart',
              'logs',
              'pull',
              'recreate',
              'upgrade',
            ])
              TerminalMenuAction(
                'compose:$action',
                dt(context, 'compose.$action'),
                Icons.layers_outlined,
                enabled: plus && connected,
              ),
          ],
        ),
    ], position);
    if (!mounted || pane.closed) return;
    switch (choice) {
      case 'ai':
        widget.onAi('```shell\n$text\n```');
        pane.viewController.clearSelection();
      case 'find':
        _openSearch();
      case 'paste':
        await _paste();
      case 'copy':
        _copy();
      case 'selection':
        await Clipboard.setData(ClipboardData(text: text));
        pane.terminal.paste(text);
      case 'clear':
        pane.terminal.write('\x1b[H\x1b[2J\x1b[3J');
      case 'reconnect':
        await widget.workspace.reconnect(pane);
      case 'path':
        final result = await pane.commands.execute(
          'pwd',
          'sftp-pwd',
          timeout: const Duration(seconds: 10),
        );
        if (!mounted || pane.closed) return;
        final path = (result['output'] as String? ?? '')
            .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.startsWith('/'))
            .lastOrNull;
        if (result['ok'] == true && result['exitCode'] == 0 && path != null) {
          widget.onSyncPath(path);
        } else {
          terminalNotice(
            context,
            result['error']?.toString() ?? dt(context, 'sftp.pathFailed'),
          );
        }
      case 'dockerShell':
        widget.workspace.input(
          pane,
          'docker exec -it $trimmed sh\n',
          synchronize: false,
        );
      case 'dockerStop':
        widget.workspace.input(
          pane,
          'docker stop $trimmed\n',
          synchronize: false,
        );
      case 'dockerRestart':
        widget.workspace.input(
          pane,
          'docker restart $trimmed\n',
          synchronize: false,
        );
      case 'dockerLogs':
        widget.workspace.input(
          pane,
          'docker logs --tail=500 -f $trimmed\n',
          synchronize: false,
        );
      case 'dockerRemove':
        final confirmed = await showAppDialog<bool>(
          context: context,
          builder: (context) => DesktopManagementDialog(
            title: dt(context, 'dockerRemove'),
            width: 440,
            body: Text('docker rm -f $trimmed'),
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
        );
        if (confirmed != true || !mounted || pane.closed) return;
        widget.workspace.input(
          pane,
          'docker rm -f $trimmed\n',
          synchronize: false,
        );
      case final String value when value.startsWith('compose:'):
        final action = value.substring(8);
        final suffix = {
          'up': 'up -d',
          'down': 'down',
          'restart': 'restart',
          'logs': 'logs -f',
          'pull': 'pull',
          'recreate': 'up -d --force-recreate',
          'upgrade': 'pull && docker compose -f ${_quote(trimmed)} up -d',
        }[action]!;
        widget.workspace.input(
          pane,
          'docker compose -f ${_quote(trimmed)} $suffix\n',
          synchronize: false,
        );
    }
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
  void _link(TapUpDetails details, CellOffset cell) {
    widget.onFocus();
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
    final link = terminalLinkAt(pane.terminal, cell);
    if (link != null) {
      unawaited(launchUrl(link, mode: LaunchMode.externalApplication));
    }
  }

  void _selectionEnd(PointerUpEvent event) {
    if (!_primarySelection) return;
    final text = selected;
    if (text.isEmpty || text == _lastSelection) return;
    _lastSelection = text;
    if (ref
            .read(effectiveDesktopTerminalSettingsProvider)
            .behavior['autoShowContextMenu'] ==
        true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selected.isNotEmpty) {
          unawaited(_contextMenu(event.position));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(effectiveDesktopTerminalSettingsProvider);
    final themes =
        ref.watch(desktopTerminalThemesProvider).valueOrNull ??
        const <String, dynamic>{};
    final rules =
        ref.watch(desktopHighlightRulesProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    pane.highlighter.configure(settings, rules);
    final transparent = settings.background['mode'] == 'image';
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: (event) {
              _primarySelection = event.buttons == kPrimaryMouseButton;
              widget.onFocus();
            },
            onPointerUp: _selectionEnd,
            child: TerminalView(
              pane.terminal,
              key: pane.viewKey,
              controller: pane.viewController,
              focusNode: pane.focusNode,
              autofocus: widget.workspace.activeTab?.activePane == pane,
              scrollController: pane.scrollController,
              theme: desktopTerminalTheme(
                settings,
                themes,
                transparent: transparent,
              ),
              backgroundOpacity: transparent ? 0 : 1,
              textStyle: TerminalStyle(
                fontSize: (settings.fontSize + _fontDelta).clamp(6, 30),
                fontFamily: settings.fontFamily,
              ),
              padding: const EdgeInsets.all(8),
              onKeyEvent: _key,
              onSecondaryTapUp: (details, _) =>
                  _contextMenu(details.globalPosition),
              onTapUp: _link,
            ),
          ),
        ),
        if (pane.status != DesktopTerminalStatus.connected)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.colors.card.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pane.status == DesktopTerminalStatus.connecting)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pane.error ?? dt(context, pane.status.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (pane.status != DesktopTerminalStatus.connecting)
                      TextButton(
                        onPressed: () => widget.workspace.reconnect(pane),
                        child: Text(dt(context, 'reconnect')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_searchOpen)
          Positioned(
            top: 8,
            right: 8,
            left: 8,
            child: Align(alignment: Alignment.topRight, child: _searchPanel()),
          ),
      ],
    );
  }

  Widget _searchPanel() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 450),
    child: Material(
      color: context.colors.card,
      elevation: 5,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final input = TextField(
              controller: _query,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: dt(context, 'find'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 35,
                  minHeight: 24,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '${_matches.isEmpty ? 0 : _current + 1}/${_matches.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              onChanged: (_) {
                _current = 0;
                _search();
              },
              onSubmitted: (_) =>
                  _next(HardwareKeyboard.instance.isShiftPressed ? -1 : 1),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constraints.maxWidth >= 400)
                  Row(
                    children: [
                      Expanded(child: input),
                      const SizedBox(width: 8),
                      _searchActions(),
                    ],
                  )
                else ...[
                  input,
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _searchActions(),
                    ),
                  ),
                ],
                if (_searchError != null)
                  Text(
                    _searchError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.danger,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _searchActions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final direction in [-1, 1])
        IconButton(
          onPressed: _matches.isEmpty ? null : () => _next(direction),
          icon: Icon(
            direction < 0 ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 16,
          ),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      for (final item in [
        ('Aa', _caseSensitive),
        ('ab', _wholeWord),
        ('.*', _regex),
      ])
        TextButton(
          onPressed: () {
            setState(() {
              switch (item.$1) {
                case 'Aa':
                  _caseSensitive = !_caseSensitive;
                case 'ab':
                  _wholeWord = !_wholeWord;
                case '.*':
                  _regex = !_regex;
              }
            });
            _search();
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(28, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            foregroundColor: item.$2
                ? context.colors.accent
                : context.colors.text,
            backgroundColor: item.$2 ? context.colors.accentSoft : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          child: Text(item.$1, style: const TextStyle(fontSize: 11)),
        ),
      IconButton(
        onPressed: _closeSearch,
        icon: const TerminalIcon(Icons.close),
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ],
  );
}
