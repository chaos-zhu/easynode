import 'dart:async' show Timer;
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../state/terminal_providers.dart';
import 'terminal_bottom_menu.dart';
import 'terminal_session.dart';
import 'terminal_session_manager.dart';

class TerminalShellPage extends ConsumerStatefulWidget {
  const TerminalShellPage({super.key});

  @override
  ConsumerState<TerminalShellPage> createState() => _TerminalShellPageState();
}

class _TerminalShellPageState extends ConsumerState<TerminalShellPage> {
  static final RegExp _urlPattern = RegExp(
    "((https?|ftp):\\/\\/[^\\s<>\"']+|www\\.[^\\s<>\"']+)",
    caseSensitive: false,
  );

  double _lastKeyboardHeight = 0;
  bool _showKeyPanel = false;
  bool _allowTerminalFocus = true;
  final FocusNode _terminalFocusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, VoidCallback> _selectionListeners = {};
  final Map<String, _TerminalSearchState> _searchStates = {};
  String? _touchSelectingSessionId;
  final Map<String, Offset> _touchSelectionStartPositions = {};
  bool _showSearchBar = false;
  Timer? _searchDebounce;

  TerminalSessionManager get _manager =>
      ref.read(terminalSessionManagerProvider);

  void _onToggleInput() {
    if (_showSearchBar) _closeSearchBar();
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardUp) {
      _terminalFocusNode.unfocus();
      setState(() {
        _showKeyPanel = true;
        _allowTerminalFocus = false;
      });
    } else {
      setState(() => _allowTerminalFocus = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _terminalFocusNode.requestFocus();
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _showKeyPanel) {
          setState(() => _showKeyPanel = false);
        }
      });
    }
  }

  Future<void> _closeActive() async {
    final manager = _manager;
    final active = manager.activeSession;
    if (active == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await manager.closeSession(active.id);
    if (mounted && manager.sessions.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSessionBindings();
  }

  void _syncSessionBindings() {
    final liveIds = <String>{};
    for (final session in _manager.sessions) {
      liveIds.add(session.id);
      if (_selectionListeners.containsKey(session.id)) continue;
      void listener() {
        if (mounted) setState(() {});
      }

      session.viewController.addListener(listener);
      _selectionListeners[session.id] = listener;
    }

    final removedIds = _selectionListeners.keys
        .where((id) => !liveIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _selectionListeners.remove(id);
      _searchStates.remove(id)?.dispose();
    }
  }

  String? _selectedText(TerminalSession session) {
    final selection = session.viewController.selection;
    if (selection == null) return null;
    final text = session.controller.terminal.buffer.getText(selection).trim();
    return text.isEmpty ? null : text;
  }

  String? _normalizeUrl(String raw) {
    final match = _urlPattern.firstMatch(raw.trim());
    if (match == null) return null;
    var url = match.group(0)!;
    url = url.replaceFirst(RegExp(r'[),.;:!?]+$'), '');
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    return Uri.tryParse(url)?.hasScheme == true ? url : null;
  }

  String? _extractUrlAtOffset(TerminalSession session, CellOffset offset) {
    final lines = session.controller.terminal.buffer.lines;
    var startLine = offset.y;
    while (startLine > 0 && lines[startLine].isWrapped) {
      startLine--;
    }
    var endLine = offset.y;
    while (endLine + 1 < lines.length && lines[endLine + 1].isWrapped) {
      endLine++;
    }

    final textBuffer = StringBuffer();
    var tappedTextOffset = 0;
    for (var lineIndex = startLine; lineIndex <= endLine; lineIndex++) {
      final line = lines[lineIndex];
      final lineText = line.getText(0, line.getTrimmedLength());
      if (lineIndex < offset.y) {
        tappedTextOffset += lineText.length;
      } else if (lineIndex == offset.y) {
        tappedTextOffset += offset.x.clamp(0, lineText.length);
      }
      textBuffer.write(lineText);
    }

    final text = textBuffer.toString();
    if (text.isEmpty) return null;
    for (final match in _urlPattern.allMatches(text)) {
      final raw = match.group(0)!;
      final normalized = _normalizeUrl(raw);
      if (normalized == null) continue;
      if (tappedTextOffset >= match.start && tappedTextOffset < match.end) {
        return normalized;
      }
    }
    return null;
  }

  Future<void> _onTerminalTap(
    TerminalSession session,
    CellOffset offset,
  ) async {
    final url = _extractUrlAtOffset(session, offset);
    if (url == null || !mounted) return;
    final l = AppLocalizations.of(context);
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('terminal.linkDialogTitle')),
        content: Text(l.trf('terminal.linkDialogBody', [url])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.tr('terminal.openBrowser')),
          ),
        ],
      ),
    );
    if (shouldOpen != true) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      _showTerminalSnack(l.tr('terminal.openLinkFailed'));
    }
  }

  RenderTerminal? _renderTerminalFor(TerminalSession session) {
    final state = session.viewKey.currentState;
    if (state == null || !state.mounted) return null;
    return state.renderTerminal;
  }

  CellOffset? _cellOffsetForGlobalPosition(
    TerminalSession session,
    Offset globalPosition,
  ) {
    final render = _renderTerminalFor(session);
    if (render == null) return null;
    final local = render.globalToLocal(globalPosition);
    return render.getCellOffset(local);
  }

  void _handleLinkTap(TerminalSession session, TapUpDetails details) {
    final offset = _cellOffsetForGlobalPosition(
      session,
      details.globalPosition,
    );
    if (offset == null) return;
    _onTerminalTap(session, offset);
  }

  void _handleSelectionStart(
    TerminalSession session,
    LongPressStartDetails details,
  ) {
    final render = _renderTerminalFor(session);
    if (render == null) return;
    _touchSelectingSessionId = session.id;
    final localPosition = render.globalToLocal(details.globalPosition);
    _touchSelectionStartPositions[session.id] = localPosition;
    render.selectWord(localPosition);
  }

  void _handleSelectionUpdate(
    TerminalSession session,
    LongPressMoveUpdateDetails details,
  ) {
    if (_touchSelectingSessionId != session.id) return;
    final render = _renderTerminalFor(session);
    final from = _touchSelectionStartPositions[session.id];
    if (render == null || from == null) return;
    final to = render.globalToLocal(details.globalPosition);
    render.selectWord(from, to);
  }

  void _handleSelectionEnd(TerminalSession session) {
    if (_touchSelectingSessionId == session.id) {
      _touchSelectingSessionId = null;
    }
    _touchSelectionStartPositions.remove(session.id);
  }

  void _showTerminalSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.viewPaddingOf(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            (insets.bottom > 0 ? insets.bottom : padding.bottom) + 12,
          ),
        ),
      );
  }

  BufferRange? _normalizedSelection(TerminalSession session) {
    return session.viewController.selection?.normalized;
  }

  Offset? _selectionHandleOffset(
    TerminalSession session, {
    required bool start,
  }) {
    final render = _renderTerminalFor(session);
    final selection = _normalizedSelection(session);
    if (render == null || selection == null) return null;
    final cell = start ? selection.begin : selection.end;
    var offset = render.getOffset(cell);
    if (!start) {
      offset = offset.translate(render.cellSize.width, render.cellSize.height);
    } else {
      offset = offset.translate(0, render.cellSize.height);
    }
    return offset;
  }

  void _updateSelectionHandle(
    TerminalSession session, {
    required bool start,
    required DragUpdateDetails details,
  }) {
    final buffer = session.controller.terminal.buffer;
    final selection = _normalizedSelection(session);
    final target = _cellOffsetForGlobalPosition(
      session,
      details.globalPosition,
    );
    if (selection == null || target == null) return;
    final begin = start ? target : selection.begin;
    final end = start ? selection.end : target;
    session.viewController.setSelection(
      buffer.createAnchorFromOffset(begin),
      buffer.createAnchorFromOffset(end),
    );
  }

  Offset? _selectionMenuOffset(TerminalSession session) {
    final render = _renderTerminalFor(session);
    final selection = _normalizedSelection(session);
    if (render == null || selection == null) return null;
    final beginOffset = render.getOffset(selection.begin);
    final boxSize = render.size;
    const menuWidth = 200.0;
    const menuHeight = 44.0;
    const gap = 12.0;
    final preferredLeft = beginOffset.dx + gap;
    final preferredTop = beginOffset.dy - menuHeight - gap;
    final left = preferredLeft.clamp(8.0, boxSize.width - menuWidth - 8.0);
    final top = preferredTop < 8.0
        ? (beginOffset.dy + render.cellSize.height + gap).clamp(
            8.0,
            boxSize.height - menuHeight - 8.0,
          )
        : preferredTop.clamp(8.0, boxSize.height - menuHeight - 8.0);
    return Offset(left, top);
  }

  Future<void> _copySelection(TerminalSession session) async {
    final text = _selectedText(session);
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    session.viewController.clearSelection();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    _showTerminalSnack(l.tr('terminal.selectionCopied'));
  }

  Future<void> _pasteToTerminal(TerminalSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    session.controller.writeInput(text);
    session.viewController.clearSelection();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    _showTerminalSnack(l.tr('terminal.pasted'));
  }

  void _clearTerminal(TerminalSession session) {
    session.controller.clearTerminal();
    session.viewController.clearSelection();
    _searchStates.remove(session.id)?.dispose();
    final l = AppLocalizations.of(context);
    _showTerminalSnack(l.tr('terminal.cleared'));
  }

  void _toggleSearchBar() {
    if (_showSearchBar) {
      _closeSearchBar();
    } else {
      setState(() => _showSearchBar = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _closeSearchBar() {
    _searchDebounce?.cancel();
    final active = _manager.activeSession;
    if (active != null) {
      _searchStates.remove(active.id)?.dispose();
    }
    _searchCtrl.clear();
    setState(() => _showSearchBar = false);
    _searchFocusNode.unfocus();
    if (active != null && _allowTerminalFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocusNode.requestFocus();
      });
    }
  }

  void _onSearchTextChanged(TerminalSession session, String text) {
    _searchDebounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      _searchStates.remove(session.id)?.dispose();
      setState(() {});
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(session, query);
    });
  }

  Future<void> _runSearch(TerminalSession session, String query) async {
    if (query.isEmpty) return;
    _searchStates.remove(session.id)?.dispose();
    final state = _buildSearchState(session, query);
    _searchStates[session.id] = state;
    session.viewController.clearSelection();
    if (state.matches.isNotEmpty) {
      _applySearchHighlight(session, state);
    }
    setState(() {});
  }

  void _jumpSearch(TerminalSession session, bool forward) {
    final state = _searchStates[session.id];
    if (state == null || state.matches.isEmpty) return;
    if (forward) {
      state.next();
    } else {
      state.previous();
    }
    _applySearchHighlight(session, state);
    setState(() {});
  }

  _TerminalSearchState _buildSearchState(
    TerminalSession session,
    String query,
  ) {
    final terminal = session.controller.terminal;
    final matches = <_TerminalSearchMatch>[];
    for (var lineIndex = 0; lineIndex < terminal.buffer.height; lineIndex++) {
      final line = terminal.buffer.lines[lineIndex];
      final text = line.getText(0, line.getTrimmedLength());
      if (text.isEmpty) continue;
      var start = 0;
      while (start <= text.length - query.length) {
        final matchIndex = text.indexOf(query, start);
        if (matchIndex < 0) break;
        matches.add(
          _TerminalSearchMatch(
            line: lineIndex,
            start: matchIndex,
            end: matchIndex + query.length,
          ),
        );
        start = matchIndex + query.length;
      }
    }
    return _TerminalSearchState(query: query, matches: matches);
  }

  void _applySearchHighlight(
    TerminalSession session,
    _TerminalSearchState state,
  ) {
    state.highlight?.dispose();
    if (state.matches.isEmpty) return;
    final current = state.current;
    final buffer = session.controller.terminal.buffer;
    state.highlight = session.viewController.highlight(
      p1: buffer.createAnchor(current.start, current.line),
      p2: buffer.createAnchor(current.end, current.line),
      color: Colors.yellowAccent.withValues(alpha: 0.55),
    );
    final lineHeight = session.viewKey.currentState?.renderTerminal.lineHeight;
    if (lineHeight != null && session.scrollController.hasClients) {
      final target = (current.line * lineHeight).clamp(
        0.0,
        session.scrollController.position.maxScrollExtent,
      );
      session.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final session in _manager.sessions) {
      final listener = _selectionListeners[session.id];
      if (listener != null) {
        session.viewController.removeListener(listener);
      }
    }
    for (final state in _searchStates.values) {
      state.dispose();
    }
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(terminalSessionManagerProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (_terminalFocusNode.hasFocus && bottomInset > _lastKeyboardHeight) {
      _lastKeyboardHeight = bottomInset;
    }
    final keyboardVisible = _terminalFocusNode.hasFocus && bottomInset > 0;

    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final panelHeight = _lastKeyboardHeight > 0
        ? (_lastKeyboardHeight - bottomSafe).clamp(200.0, 600.0)
        : 260.0;
    final panelSpace = _showKeyPanel ? panelHeight : 0.0;
    final bottomSpace = max(bottomInset, panelSpace + bottomSafe) - panelSpace;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        _syncSessionBindings();
        final sessions = manager.sessions.toList(growable: false);
        final active = manager.activeSession;
        final activeIndex = active == null
            ? 0
            : sessions.indexWhere((session) => session.id == active.id);
        final activeRange = active == null
            ? null
            : _normalizedSelection(active);
        final activeSearchState = active == null
            ? null
            : _searchStates[active.id];
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            bottom: false,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    _TerminalTopBar(
                      active: active,
                      showSearchBar: _showSearchBar,
                      onClose: _closeActive,
                      onSearchToggle: active == null ? null : _toggleSearchBar,
                      onReconnect: active == null
                          ? null
                          : () => manager.reconnect(active.id),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: Colors.black,
                        child: sessions.isEmpty
                            ? Center(
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).tr('terminal.noActive'),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              )
                            : FocusScope(
                                canRequestFocus: _allowTerminalFocus,
                                child: IndexedStack(
                                  index: activeIndex < 0 ? 0 : activeIndex,
                                  children: [
                                    for (final session in sessions)
                                      Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          TerminalView(
                                            key: session.viewKey,
                                            session.controller.terminal,
                                            controller: session.viewController,
                                            scrollController:
                                                session.scrollController,
                                            focusNode: session.id == active?.id
                                                ? _terminalFocusNode
                                                : null,
                                            autofocus: session.id == active?.id,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 6,
                                            ),
                                          ),
                                          if (session.id == active?.id)
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTapUp: (details) =>
                                                    _handleLinkTap(
                                                      session,
                                                      details,
                                                    ),
                                                onLongPressStart: (details) =>
                                                    _handleSelectionStart(
                                                      session,
                                                      details,
                                                    ),
                                                onLongPressMoveUpdate:
                                                    (details) =>
                                                        _handleSelectionUpdate(
                                                          session,
                                                          details,
                                                        ),
                                                onLongPressEnd: (_) =>
                                                    _handleSelectionEnd(
                                                      session,
                                                    ),
                                              ),
                                            ),
                                          if (session.id == active?.id &&
                                              activeRange != null) ...[
                                            _SelectionContextMenu(
                                              offset: _selectionMenuOffset(
                                                session,
                                              ),
                                              onCopy: () =>
                                                  _copySelection(session),
                                              onPaste: () =>
                                                  _pasteToTerminal(session),
                                              onClear: () =>
                                                  _clearTerminal(session),
                                            ),
                                            _SelectionHandle(
                                              offset: _selectionHandleOffset(
                                                session,
                                                start: true,
                                              ),
                                              alignLeft: true,
                                              onDragUpdate: (details) =>
                                                  _updateSelectionHandle(
                                                    session,
                                                    start: true,
                                                    details: details,
                                                  ),
                                            ),
                                            _SelectionHandle(
                                              offset: _selectionHandleOffset(
                                                session,
                                                start: false,
                                              ),
                                              alignLeft: false,
                                              onDragUpdate: (details) =>
                                                  _updateSelectionHandle(
                                                    session,
                                                    start: false,
                                                    details: details,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    TerminalBottomBar(
                      manager: manager,
                      active: active,
                      controller: active?.controller,
                      onInput: (value) =>
                          manager.activeSession?.controller.writeInput(value),
                      showKeyPanel: _showKeyPanel,
                      onToggleInput: _onToggleInput,
                      panelHeight: panelHeight,
                      keyboardVisible: keyboardVisible,
                    ),
                    SizedBox(height: bottomSpace),
                  ],
                ),
                if (active != null && _showSearchBar)
                  Positioned(
                    top: _kTopBarHeight + 6,
                    right: 8,
                    child: _TerminalSearchBar(
                      controller: _searchCtrl,
                      focusNode: _searchFocusNode,
                      resultText: activeSearchState == null
                          ? null
                          : AppLocalizations.of(
                              context,
                            ).trf('terminal.findResults', [
                              activeSearchState.query,
                              '${activeSearchState.index + 1}',
                              '${activeSearchState.matches.length}',
                            ]),
                      onChanged: (text) =>
                          _onSearchTextChanged(active, text),
                      onPrevious: activeSearchState == null
                          ? null
                          : () => _jumpSearch(active, false),
                      onNext: activeSearchState == null
                          ? null
                          : () => _jumpSearch(active, true),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TerminalTopBar extends StatelessWidget {
  const _TerminalTopBar({
    required this.active,
    required this.showSearchBar,
    required this.onClose,
    required this.onSearchToggle,
    required this.onReconnect,
  });

  final TerminalSession? active;
  final bool showSearchBar;
  final VoidCallback onClose;
  final VoidCallback? onSearchToggle;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final activeSession = active;
    final l = AppLocalizations.of(context);
    return Container(
      height: _kTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: activeSession == null
                ? Text(l.tr('terminal.title'), overflow: TextOverflow.ellipsis)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeSession.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Row(
                        children: [
                          _StatusDot(status: activeSession.status),
                          const SizedBox(width: 6),
                          Text(
                            _statusText(l, activeSession.status),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          IconButton(
            tooltip: l.tr('common.search'),
            onPressed: onSearchToggle,
            icon: Icon(
              Icons.search,
              color: showSearchBar
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            tooltip: l.tr('terminal.reconnect'),
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l.tr('terminal.closeTerminal'),
            onPressed: activeSession == null ? null : onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
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
    return Icon(Icons.circle, size: 9, color: color);
  }
}

class _SelectionContextMenu extends StatelessWidget {
  const _SelectionContextMenu({
    required this.offset,
    required this.onCopy,
    required this.onPaste,
    required this.onClear,
  });

  final Offset? offset;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final menuOffset = offset;
    if (menuOffset == null) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Positioned(
      left: menuOffset.dx,
      top: menuOffset.dy,
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF5161A22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SelectionMenuItem(
                label: l.tr('terminal.selection.copy'),
                onTap: onCopy,
              ),
              _SelectionMenuDivider(),
              _SelectionMenuItem(
                label: l.tr('terminal.selection.paste'),
                onTap: onPaste,
              ),
              _SelectionMenuDivider(),
              _SelectionMenuItem(
                label: l.tr('terminal.selection.clear'),
                onTap: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMenuItem extends StatelessWidget {
  const _SelectionMenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SelectionMenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _SelectionHandle extends StatelessWidget {
  const _SelectionHandle({
    required this.offset,
    required this.alignLeft,
    required this.onDragUpdate,
  });

  final Offset? offset;
  final bool alignLeft;
  final GestureDragUpdateCallback onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final handleOffset = offset;
    if (handleOffset == null) {
      return const SizedBox.shrink();
    }
    const knobRadius = 8.0;
    const stemHeight = 16.0;
    final left = alignLeft
        ? handleOffset.dx - knobRadius
        : handleOffset.dx - knobRadius;
    final top = handleOffset.dy - stemHeight;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDragUpdate,
        child: SizedBox(
          width: knobRadius * 2,
          height: stemHeight + knobRadius * 2,
          child: Column(
            children: [
              Container(
                width: 2,
                height: stemHeight,
                color: Theme.of(context).colorScheme.primary,
              ),
              Container(
                width: knobRadius * 2,
                height: knobRadius * 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalSearchBar extends StatelessWidget {
  const _TerminalSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    this.resultText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? resultText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0xF5161A22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppLocalizations.of(
                        context,
                      ).tr('common.search'),
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _SearchNavButton(
                  icon: Icons.keyboard_arrow_up,
                  onPressed: onPrevious,
                ),
                const SizedBox(width: 2),
                _SearchNavButton(
                  icon: Icons.keyboard_arrow_down,
                  onPressed: onNext,
                ),
              ],
            ),
            if (resultText != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  resultText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchNavButton extends StatelessWidget {
  const _SearchNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: Colors.white,
        disabledColor: Colors.white38,
        padding: EdgeInsets.zero,
        splashRadius: 16,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

class _TerminalSearchMatch {
  const _TerminalSearchMatch({
    required this.line,
    required this.start,
    required this.end,
  });

  final int line;
  final int start;
  final int end;
}

class _TerminalSearchState {
  _TerminalSearchState({required this.query, required this.matches});

  final String query;
  final List<_TerminalSearchMatch> matches;
  int index = 0;
  TerminalHighlight? highlight;

  _TerminalSearchMatch get current => matches[index];

  void next() {
    if (matches.isEmpty) return;
    index = (index + 1) % matches.length;
  }

  void previous() {
    if (matches.isEmpty) return;
    index = (index - 1 + matches.length) % matches.length;
  }

  void dispose() {
    highlight?.dispose();
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

const double _kTopBarHeight = 52;
