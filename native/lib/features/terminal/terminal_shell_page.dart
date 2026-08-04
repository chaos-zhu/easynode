import 'dart:async' show Timer;
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/terminal_providers.dart';
import '../../state/terminal_settings_notifier.dart';
import 'terminal_bottom_menu.dart';
import 'terminal_session.dart';
import 'terminal_session_manager.dart';
import 'terminal_settings_page.dart';

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

  // TerminalView 自己的内边距：RenderTerminal.getOffset()/globalToLocal() 返回的坐标
  // 是相对 RenderTerminal 自身（padding 内侧）的，而选区菜单/手柄/放大镜是用 Positioned
  // 摆在外层 Stack（padding 外侧）里的，两者之间正好差这一圈 padding，必须补上，
  // 否则手柄会系统性地偏离选中字符的实际边界。
  static const _terminalContentPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 6,
  );

  double _lastKeyboardHeight = 0;
  bool _showKeyPanel = false;
  bool _allowTerminalFocus = true;
  final FocusNode _terminalFocusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, VoidCallback> _selectionListeners = {};
  final Map<String, VoidCallback> _scrollListeners = {};
  final Map<String, _TerminalSearchState> _searchStates = {};
  // 当前实时触摸点（active session 的终端本地坐标），驱动放大镜显示；
  // 长按选词/拖动扩展选区完全交给 xterm 内建手势处理，这里只用 Listener 被动跟踪坐标，
  // 不参与手势竞技场，避免和 xterm 内部的 LongPressGestureRecognizer 竞争同一次触摸。
  final ValueNotifier<Offset?> _liveTouchPosition = ValueNotifier(null);
  Timer? _longPressMenuTimer;
  String? _longPressMenuSessionId;
  Offset? _longPressMenuOffset;
  Offset? _longPressPointerDownOffset;
  bool _ignoreNextTapUp = false;
  bool _showSearchBar = false;
  Timer? _searchDebounce;
  Timer? _scrollIdleTimer;
  Timer? _selectionAutoScrollTimer;
  TerminalSession? _selectionDragSession;
  Offset? _selectionDragGlobalPosition;
  bool _selectionDragIsStart = false;
  bool _selectionHandleDragging = false;
  bool _terminalScrolling = false;
  bool _scrollFrameScheduled = false;

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
        // 系统键盘可能是用户手动收起的，此时 FocusNode 仍然 hasFocus，
        // 单纯 requestFocus() 是空操作，必须走 requestKeyboard() 才能强制重新 show()
        final activeSession = _manager.activeSession;
        if (activeSession != null) {
          activeSession.viewKey.currentState?.requestKeyboard();
        } else {
          _terminalFocusNode.requestFocus();
        }
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
      if (!_selectionListeners.containsKey(session.id)) {
        void listener() {
          if (!mounted) return;
          if (session.viewController.selection == null &&
              _longPressMenuSessionId == session.id) {
            _clearLongPressMenu();
            return;
          }
          setState(() {});
        }

        session.viewController.addListener(listener);
        _selectionListeners[session.id] = listener;
      }

      if (!_scrollListeners.containsKey(session.id)) {
        void listener() => _handleTerminalScroll(session);

        session.scrollController.addListener(listener);
        _scrollListeners[session.id] = listener;
      }
    }

    final removedIds = _selectionListeners.keys
        .where((id) => !liveIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _selectionListeners.remove(id);
      _scrollListeners.remove(id);
      _searchStates.remove(id)?.dispose();
    }
  }

  void _handleTerminalScroll(TerminalSession session) {
    if (!mounted || _manager.activeSession?.id != session.id) return;
    if (_scrollFrameScheduled) return;
    _scrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFrameScheduled = false;
      if (!mounted || _manager.activeSession?.id != session.id) return;
      _scrollIdleTimer?.cancel();
      setState(() => _terminalScrolling = true);
      _scrollIdleTimer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted || _manager.activeSession?.id != session.id) return;
        setState(() => _terminalScrolling = false);
      });
    });
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
    if (_ignoreNextTapUp) {
      _ignoreNextTapUp = false;
      return;
    }
    _clearLongPressMenu();
    final offset = _cellOffsetForGlobalPosition(
      session,
      details.globalPosition,
    );
    if (offset == null) return;
    // 点击命中链接时走原有的打开链接流程；未命中链接时兜底尝试唤起键盘——
    // 覆盖 xterm 内部 _onTapDown 在残留选区场景下不会请求键盘的情况，requestKeyboard() 本身幂等
    if (_extractUrlAtOffset(session, offset) == null) {
      session.viewKey.currentState?.requestKeyboard();
      return;
    }
    _onTerminalTap(session, offset);
  }

  // RenderTerminal.getOffset()/globalToLocal() 返回的是相对 RenderTerminal 自身（也就是
  // TerminalView padding 内侧）的坐标；而选区菜单/手柄/放大镜都是用 Positioned 摆在外层
  // Stack（padding 外侧，和 TerminalView 同级）里的，所以要统一补上这一圈 padding，
  // 否则这些浮层会系统性地偏离选中字符的实际像素位置。
  Offset _toOverlayLocal(Offset renderLocalOffset) {
    return renderLocalOffset + _terminalContentPadding.topLeft;
  }

  Offset? _overlayLocalForGlobalPosition(
    TerminalSession session,
    Offset globalPosition,
  ) {
    final render = _renderTerminalFor(session);
    if (render == null) return null;
    return _toOverlayLocal(render.globalToLocal(globalPosition));
  }

  // 被动跟踪原始触摸点，只用来驱动放大镜定位——不调用 selectWord/setSelection，
  // 长按选词和拖动扩展选区完全由 xterm 内部的 TerminalGestureHandler 处理。
  void _trackTouchPosition(TerminalSession session, Offset globalPosition) {
    final offset = _overlayLocalForGlobalPosition(session, globalPosition);
    if (offset == null) return;
    _liveTouchPosition.value = offset;
  }

  void _clearTouchPosition() {
    if (_liveTouchPosition.value != null) {
      _liveTouchPosition.value = null;
    }
  }

  void _clearPendingLongPressMenu() {
    _longPressMenuTimer?.cancel();
    _longPressMenuTimer = null;
    _longPressPointerDownOffset = null;
  }

  void _clearLongPressMenu() {
    _clearPendingLongPressMenu();
    _ignoreNextTapUp = false;
    if (_longPressMenuSessionId == null && _longPressMenuOffset == null) return;
    setState(() {
      _longPressMenuSessionId = null;
      _longPressMenuOffset = null;
    });
  }

  void _handleTerminalPointerDown(
    TerminalSession session,
    PointerDownEvent event,
  ) {
    _trackTouchPosition(session, event.position);
    final menuOffset = _overlayLocalForGlobalPosition(session, event.position);
    if (menuOffset == null) return;
    _longPressPointerDownOffset = menuOffset;
    _longPressMenuTimer?.cancel();
    _longPressMenuTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _manager.activeSession?.id != session.id) return;
      _ignoreNextTapUp = true;
      setState(() {
        _longPressMenuSessionId = session.id;
        _longPressMenuOffset = menuOffset;
      });
    });
  }

  void _handleTerminalPointerMove(
    TerminalSession session,
    PointerMoveEvent event,
  ) {
    _trackTouchPosition(session, event.position);
    final start = _longPressPointerDownOffset;
    final current = _overlayLocalForGlobalPosition(session, event.position);
    if (start == null || current == null) return;
    if ((current - start).distanceSquared > 144) {
      _ignoreNextTapUp = false;
      _clearPendingLongPressMenu();
    }
  }

  void _handleTerminalPointerUp() {
    _clearPendingLongPressMenu();
    _clearTouchPosition();
  }

  void _handleTerminalPointerCancel() {
    _clearPendingLongPressMenu();
    _clearTouchPosition();
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
    final selection = session.viewController.selection;
    if (render == null || selection == null) return null;
    // selection.end 已经是「选区之后第一个格子」的位置（exclusive），
    // getOffset(end) 本身就是选区的右边界——不能再额外加一个 cellSize.width，
    // 否则会多移一整格，导致终点手柄盖住选区后面的下一个字符。
    //
    // 手柄位置必须使用未 normalized 的 base/extent。用户把终点手柄反向拖过起点时，
    // normalized.begin 会变成正在拖动的终点，导致视觉上的起点手柄跟着手指跑。
    final cell = start ? selection.begin : selection.end;
    final offset = render.getOffset(cell).translate(0, render.cellSize.height);
    return _toOverlayLocal(offset);
  }

  void _updateSelectionHandleAtGlobalPosition(
    TerminalSession session, {
    required bool start,
    required Offset globalPosition,
  }) {
    final buffer = session.controller.terminal.buffer;
    final selection = session.viewController.selection;
    final target = _cellOffsetForGlobalPosition(
      session,
      globalPosition,
    );
    if (selection == null || target == null) return;
    final begin = start ? target : selection.begin;
    final end = start ? selection.end : target;
    session.viewController.setSelection(
      buffer.createAnchorFromOffset(begin),
      buffer.createAnchorFromOffset(end),
    );
  }

  void _handleHandleDragStart(
    TerminalSession session,
    DragStartDetails details,
  ) {
    setState(() => _selectionHandleDragging = true);
    _selectionDragSession = session;
    _selectionDragGlobalPosition = details.globalPosition;
    _trackTouchPosition(session, details.globalPosition);
  }

  void _handleHandleDragUpdate(
    TerminalSession session, {
    required bool start,
    required DragUpdateDetails details,
  }) {
    _selectionDragSession = session;
    _selectionDragIsStart = start;
    _selectionDragGlobalPosition = details.globalPosition;
    _updateSelectionHandleAtGlobalPosition(
      session,
      start: start,
      globalPosition: details.globalPosition,
    );
    _updateSelectionAutoScroll();
    _trackTouchPosition(session, details.globalPosition);
  }

  double _selectionAutoScrollDelta(
    RenderTerminal render,
    Offset globalPosition,
  ) {
    const edgeExtent = 56.0;
    final localY = render.globalToLocal(globalPosition).dy;
    final viewportHeight = render.size.height;
    if (viewportHeight <= 0) return 0;

    double direction;
    double distance;
    if (localY < edgeExtent) {
      direction = -1;
      distance = edgeExtent - localY;
    } else if (localY > viewportHeight - edgeExtent) {
      direction = 1;
      distance = localY - (viewportHeight - edgeExtent);
    } else {
      return 0;
    }

    final strength = (distance / edgeExtent).clamp(0.0, 2.0);
    return direction * render.lineHeight * (0.35 + strength * 1.35);
  }

  void _updateSelectionAutoScroll() {
    final session = _selectionDragSession;
    final globalPosition = _selectionDragGlobalPosition;
    final render = session == null ? null : _renderTerminalFor(session);
    if (session == null || globalPosition == null || render == null) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }
    final delta = _selectionAutoScrollDelta(render, globalPosition);
    if (delta == 0 || !session.scrollController.hasClients) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }
    _selectionAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickSelectionAutoScroll(),
    );
  }

  void _tickSelectionAutoScroll() {
    final session = _selectionDragSession;
    final globalPosition = _selectionDragGlobalPosition;
    if (session == null ||
        globalPosition == null ||
        _manager.activeSession?.id != session.id ||
        !session.scrollController.hasClients) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }
    final render = _renderTerminalFor(session);
    if (render == null) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }
    final delta = _selectionAutoScrollDelta(render, globalPosition);
    if (delta == 0) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }

    final position = session.scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      _stopSelectionAutoScroll(clearDrag: false);
      return;
    }
    session.scrollController.jumpTo(target);
    _updateSelectionHandleAtGlobalPosition(
      session,
      start: _selectionDragIsStart,
      globalPosition: globalPosition,
    );
    _trackTouchPosition(session, globalPosition);
  }

  void _stopSelectionAutoScroll({required bool clearDrag}) {
    _selectionAutoScrollTimer?.cancel();
    _selectionAutoScrollTimer = null;
    if (!clearDrag) return;
    _selectionDragSession = null;
    _selectionDragGlobalPosition = null;
  }

  void _normalizeSelectionDirection(TerminalSession session) {
    final selection = session.viewController.selection;
    if (selection == null || selection.isNormalized) return;
    final normalized = selection.normalized;
    final buffer = session.controller.terminal.buffer;
    session.viewController.setSelection(
      buffer.createAnchorFromOffset(normalized.begin),
      buffer.createAnchorFromOffset(normalized.end),
    );
  }

  void _handleHandleDragEnd(TerminalSession session, DragEndDetails details) {
    _stopSelectionAutoScroll(clearDrag: true);
    _normalizeSelectionDirection(session);
    _clearTouchPosition();
    if (mounted) setState(() => _selectionHandleDragging = false);
  }

  void _handleHandleDragCancel(TerminalSession session) {
    _stopSelectionAutoScroll(clearDrag: true);
    _normalizeSelectionDirection(session);
    _clearTouchPosition();
    if (mounted) setState(() => _selectionHandleDragging = false);
  }

  Offset? _selectionMenuOffset(TerminalSession session) {
    final render = _renderTerminalFor(session);
    final selection = _normalizedSelection(session);
    if (render == null) return null;
    final contentSize = render.size;
    final overlaySize = Size(
      contentSize.width + _terminalContentPadding.horizontal,
      contentSize.height + _terminalContentPadding.vertical,
    );
    final cellHeight = render.cellSize.height;
    final Offset anchor;
    if (selection == null) {
      final longPressOffset = _longPressMenuOffset;
      if (longPressOffset == null) return null;
      anchor = longPressOffset;
    } else {
      final beginOffset = _toOverlayLocal(render.getOffset(selection.begin));
      final endOffset = _toOverlayLocal(render.getOffset(selection.end));
      final contentTop = _terminalContentPadding.top;
      final contentBottom = contentTop + contentSize.height;
      if (endOffset.dy + cellHeight < contentTop ||
          beginOffset.dy > contentBottom) {
        return null;
      }
      anchor = Offset(
        beginOffset.dy < contentTop
            ? _terminalContentPadding.left
            : beginOffset.dx,
        beginOffset.dy.clamp(contentTop, contentBottom - cellHeight),
      );
    }
    const menuWidth = 200.0;
    const menuHeight = 44.0;
    const gap = 12.0;
    final preferredLeft = anchor.dx + gap;
    final preferredTop = anchor.dy - menuHeight - gap;
    final maxLeft = max(8.0, overlaySize.width - menuWidth - 8.0);
    final maxTop = max(8.0, overlaySize.height - menuHeight - 8.0);
    final left = preferredLeft.clamp(8.0, maxLeft);
    final top = preferredTop < 8.0
        ? (anchor.dy + cellHeight + gap).clamp(8.0, maxTop)
        : preferredTop.clamp(8.0, maxTop);
    return Offset(left, top);
  }

  Future<void> _copySelection(TerminalSession session) async {
    final text = _selectedText(session);
    if (text == null) {
      _clearLongPressMenu();
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    session.viewController.clearSelection();
    _clearLongPressMenu();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    _showTerminalSnack(l.tr('terminal.selectionCopied'));
  }

  Future<void> _pasteToTerminal(TerminalSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _clearLongPressMenu();
      return;
    }
    session.controller.writeInput(text);
    session.viewController.clearSelection();
    _clearLongPressMenu();
  }

  void _clearTerminal(TerminalSession session) {
    session.controller.clearTerminal();
    session.viewController.clearSelection();
    _clearLongPressMenu();
    _searchStates.remove(session.id)?.dispose();
  }

  // void _toggleSearchBar() {
  //   if (_showSearchBar) {
  //     _closeSearchBar();
  //   } else {
  //     setState(() => _showSearchBar = true);
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       if (mounted) _searchFocusNode.requestFocus();
  //     });
  //   }
  // }

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
    _scrollIdleTimer?.cancel();
    _stopSelectionAutoScroll(clearDrag: true);
    for (final session in _manager.sessions) {
      final listener = _selectionListeners[session.id];
      if (listener != null) {
        session.viewController.removeListener(listener);
      }
      final scrollListener = _scrollListeners[session.id];
      if (scrollListener != null) {
        session.scrollController.removeListener(scrollListener);
      }
    }
    for (final state in _searchStates.values) {
      state.dispose();
    }
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _terminalFocusNode.dispose();
    _longPressMenuTimer?.cancel();
    _liveTouchPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(terminalSessionManagerProvider);
    final termSettings = ref.watch(terminalSettingsProvider);
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
                      onClose: _closeActive,
                      onSettings: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TerminalSettingsPage(),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: termSettings.terminalTheme.background,
                        child: sessions.isEmpty
                            ? Center(
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).tr('terminal.noActive'),
                                  style: TextStyle(
                                    color: context.colors.softMuted,
                                  ),
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
                                            theme: termSettings.terminalTheme,
                                            textStyle:
                                                termSettings.terminalStyle,
                                            focusNode: session.id == active?.id
                                                ? _terminalFocusNode
                                                : null,
                                            autofocus: session.id == active?.id,
                                            deleteDetection: true,
                                            padding: _terminalContentPadding,
                                          ),
                                          if (session.id == active?.id)
                                            Positioned.fill(
                                              // Listener 是原始指针监听，不进入手势竞技场，
                                              // 只用来给放大镜取实时触摸坐标，长按选词/拖动
                                              // 扩展选区完全交给 xterm 内建的 TerminalView 处理，
                                              // 避免和它内部的 LongPressGestureRecognizer 竞争。
                                              child: Listener(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onPointerDown: (event) =>
                                                    _handleTerminalPointerDown(
                                                      session,
                                                      event,
                                                    ),
                                                onPointerMove: (event) =>
                                                    _handleTerminalPointerMove(
                                                      session,
                                                      event,
                                                    ),
                                                onPointerUp: (_) =>
                                                    _handleTerminalPointerUp(),
                                                onPointerCancel: (_) =>
                                                    _handleTerminalPointerCancel(),
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onTapUp: (details) =>
                                                      _handleLinkTap(
                                                        session,
                                                        details,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          if (session.id == active?.id &&
                                              activeRange != null) ...[
                                            _SelectionHandle(
                                              offset: _selectionHandleOffset(
                                                session,
                                                start: true,
                                              ),
                                              knobOnTop: true,
                                              cellHeight:
                                                  _renderTerminalFor(
                                                    session,
                                                  )?.cellSize.height ??
                                                  16,
                                              onDragStart: (details) =>
                                                  _handleHandleDragStart(
                                                    session,
                                                    details,
                                                  ),
                                              onDragUpdate: (details) =>
                                                  _handleHandleDragUpdate(
                                                    session,
                                                    start: true,
                                                    details: details,
                                                  ),
                                              onDragEnd: (details) =>
                                                  _handleHandleDragEnd(
                                                    session,
                                                    details,
                                                  ),
                                              onDragCancel: () =>
                                                  _handleHandleDragCancel(
                                                    session,
                                                  ),
                                            ),
                                            _SelectionHandle(
                                              offset: _selectionHandleOffset(
                                                session,
                                                start: false,
                                              ),
                                              knobOnTop: false,
                                              cellHeight:
                                                  _renderTerminalFor(
                                                    session,
                                                  )?.cellSize.height ??
                                                  16,
                                              onDragStart: (details) =>
                                                  _handleHandleDragStart(
                                                    session,
                                                    details,
                                                  ),
                                              onDragUpdate: (details) =>
                                                  _handleHandleDragUpdate(
                                                    session,
                                                    start: false,
                                                    details: details,
                                                  ),
                                              onDragEnd: (details) =>
                                                  _handleHandleDragEnd(
                                                    session,
                                                    details,
                                                  ),
                                              onDragCancel: () =>
                                                  _handleHandleDragCancel(
                                                    session,
                                                  ),
                                            ),
                                            _TerminalMagnifier(
                                              liveTouchPosition:
                                                  _liveTouchPosition,
                                              containerSize:
                                                  _renderTerminalFor(
                                                    session,
                                                  )?.size ??
                                                  Size.zero,
                                            ),
                                          ],
                                          // 菜单必须放在手柄之后，确保它位于手柄透明热区
                                          // 上方，否则靠近选区时复制/粘贴按钮会被手柄截获。
                                          if (session.id == active?.id &&
                                              (activeRange != null ||
                                                  _longPressMenuSessionId ==
                                                      session.id) &&
                                              !_selectionHandleDragging &&
                                              !_terminalScrolling)
                                            _SelectionContextMenu(
                                              offset: _selectionMenuOffset(
                                                session,
                                              ),
                                              showCopy: activeRange != null,
                                              onCopy: () =>
                                                  _copySelection(session),
                                              onPaste: () =>
                                                  _pasteToTerminal(session),
                                              onClear: () =>
                                                  _clearTerminal(session),
                                            ),
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
                      onFocusTerminal: () {
                        if (_allowTerminalFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _terminalFocusNode.requestFocus();
                          });
                        }
                      },
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
                      onChanged: (text) => _onSearchTextChanged(active, text),
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
    required this.onClose,
    required this.onSettings,
  });

  final TerminalSession? active;
  final VoidCallback onClose;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final activeSession = active;
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: _kTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
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
          // IconButton(
          //   tooltip: l.tr('common.search'),
          //   onPressed: onSearchToggle,
          //   icon: Icon(
          //     Icons.search,
          //     color: showSearchBar
          //         ? Theme.of(context).colorScheme.primary
          //         : null,
          //   ),
          // ),
          IconButton(
            tooltip: l.tr('terminal.settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
          IconButton(
            tooltip: l.tr('terminal.closeTerminal'),
            onPressed: activeSession == null ? null : onClose,
            icon: const Icon(Icons.close, size: 21),
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
    required this.showCopy,
    required this.onCopy,
    required this.onPaste,
    required this.onClear,
  });

  final Offset? offset;
  final bool showCopy;
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
              if (showCopy) ...[
                _SelectionMenuItem(
                  label: l.tr('terminal.selection.copy'),
                  onTap: onCopy,
                ),
                _SelectionMenuDivider(),
              ],
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
    required this.knobOnTop,
    required this.cellHeight,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final Offset? offset;
  final bool knobOnTop;
  final double cellHeight;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragCancelCallback onDragCancel;

  static const double _knobRadius = 8.0;
  static const double _stemWidth = 2.0;
  // 热区比视觉图形大一圈，满足约 44 逻辑像素的最小触控目标，不改变视觉大小。
  static const double _hitPadding = 14.0;

  @override
  Widget build(BuildContext context) {
    final handleOffset = offset;
    if (handleOffset == null) {
      return const SizedBox.shrink();
    }
    // stem 竖线的高度用真实的字符格高度（随字体大小设置变化），而不是写死的像素值，
    // 这样竖线正好贴合被选中字符的上下边界，不会有间隙。
    final stemHeight = cellHeight;
    final knobDiameter = _knobRadius * 2;
    final color = Theme.of(context).colorScheme.primary;
    return Positioned(
      // 竖线和圆点整体以 handleOffset.dx（选区边界的真实像素位置）为中心水平居中，
      // 外面再包一圈透明热区方便手指拖拽，不影响视觉大小和居中效果。
      left: handleOffset.dx - _knobRadius - _hitPadding,
      top:
          handleOffset.dy -
          stemHeight -
          (knobOnTop ? knobDiameter : 0) -
          _hitPadding,
      width: _knobRadius * 2 + _hitPadding * 2,
      height: stemHeight + _knobRadius * 2 + _hitPadding * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: onDragStart,
        onPanUpdate: onDragUpdate,
        onPanEnd: onDragEnd,
        onPanCancel: onDragCancel,
        child: Padding(
          padding: const EdgeInsets.all(_hitPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (knobOnTop) _SelectionHandleKnob(color: color),
              Container(width: _stemWidth, height: stemHeight, color: color),
              if (!knobOnTop) _SelectionHandleKnob(color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionHandleKnob extends StatelessWidget {
  const _SelectionHandleKnob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SelectionHandle._knobRadius * 2,
      height: _SelectionHandle._knobRadius * 2,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TerminalMagnifier extends StatelessWidget {
  const _TerminalMagnifier({
    required this.liveTouchPosition,
    required this.containerSize,
  });

  final ValueNotifier<Offset?> liveTouchPosition;
  final Size containerSize;

  static const _size = Size(140, 90);
  static const _verticalGap = 28.0;
  static const _scale = 1.75;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: liveTouchPosition,
      builder: (context, touch, _) {
        if (touch == null) return const SizedBox.shrink();
        final maxLeft = max(4.0, containerSize.width - _size.width - 4.0);
        final left = (touch.dx - _size.width / 2).clamp(4.0, maxLeft);
        var top = touch.dy - _verticalGap - _size.height;
        if (top < 4.0) {
          // 上方空间不够（比如选中的是第一行）时，改为显示在触摸点下方。
          top = touch.dy + _verticalGap;
        }
        final magnifierCenter = Offset(
          left + _size.width / 2,
          top + _size.height / 2,
        );
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: RawMagnifier(
              size: _size,
              magnificationScale: _scale,
              focalPointOffset: touch - magnifierCenter,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                shadows: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                    autocorrect: false,
                    enableSuggestions: false,
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
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
