import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/agent_providers.dart';
import '../settings/ai_agent_settings_page.dart';
import 'agent_controller.dart';
import 'agent_feedback.dart';
import 'agent_models.dart';
import 'agent_reducer.dart';
import 'agent_selection_sheet.dart';
import 'agent_socket_client.dart';
import 'agent_ui_tokens.dart';

part 'agent_window.dart';
part 'agent_composer.dart';
part 'agent_message_view.dart';
part 'agent_tool_card.dart';
part 'agent_approval_card.dart';
part 'agent_markdown.dart';
part 'agent_history_sheet.dart';

final Highlight _agentHighlighter = Highlight()
  ..registerLanguages(builtinAllLanguages);

class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

enum _AgentScrollMode { pinned, detached }

class _AgentPanelState extends ConsumerState<AgentPanel> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  final _transcriptFocus = FocusNode(debugLabel: 'agent-transcript');
  var _isAtBottom = true;
  var _scrollMode = _AgentScrollMode.pinned;
  var _scrollingToBottom = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_handleScroll);
    Future.microtask(() => ref.read(agentControllerProvider.notifier).open());
  }

  @override
  void dispose() {
    _draft.dispose();
    _transcriptFocus.dispose();
    _scroll.removeListener(_handleScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final l = AppLocalizations.of(context);
    ref.listen(agentControllerProvider, (previous, next) {
      final oldConversation = previous?.conversation;
      final conversation = next.conversation;
      final contentChanged =
          oldConversation == null ||
          !identical(oldConversation.messages, conversation.messages) ||
          !identical(
            oldConversation.pendingApprovals,
            conversation.pendingApprovals,
          ) ||
          oldConversation.error != conversation.error;
      if (contentChanged && _scrollMode == _AgentScrollMode.pinned) {
        _scheduleScrollToBottom();
      }
    });

    return Column(
      children: [
        if (widget.showHeader) _buildHeader(context, state),
        if (state.connectionError != null)
          _AgentNotice(
            text: state.connectionError == 'No Cookie'
                ? l.tr('agent.error.loginExpired')
                : state.connectionError!,
            color: context.colors.danger,
            actionLabel: l.tr('common.retry'),
            onAction: _reconnect,
            onClose: ref
                .read(agentControllerProvider.notifier)
                .dismissConnectionError,
          )
        else if (state.conversation.plusRequired != null)
          _AgentNotice(
            text: state.conversation.plusRequired!,
            color: context.colors.warning,
            onClose: ref.read(agentControllerProvider.notifier).dismissNotices,
          )
        else if (state.conversation.notice != null)
          _AgentNotice(
            text: _noticeText(l, state.conversation.notice!),
            color: context.colors.primary,
            onClose: ref.read(agentControllerProvider.notifier).dismissNotices,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const preferredTranscriptHeight = 120.0;
              const minimumTranscriptHeight = 48.0;
              const compactDockMinHeight = 200.0;
              final preferredDockHeight =
                  constraints.maxHeight - preferredTranscriptHeight;
              final constrainedDockMinimum = math.min(
                compactDockMinHeight,
                math.max(0.0, constraints.maxHeight - minimumTranscriptHeight),
              );
              final dockMaxHeight = math.min(
                320.0,
                math.max(preferredDockHeight, constrainedDockMinimum),
              );
              return Column(
                children: [
                  Expanded(child: _buildTranscript(context, state, l)),
                  if (state.conversation.pendingApprovals.isNotEmpty &&
                      dockMaxHeight > 0)
                    AgentApprovalDock(
                      approvals: state.conversation.pendingApprovals,
                      maxHeight: dockMaxHeight,
                    ),
                ],
              );
            },
          ),
        ),
        _AgentComposer(controller: _draft, state: state, onSend: _send),
      ],
    );
  }

  Widget _buildTranscript(
    BuildContext context,
    AgentState state,
    AppLocalizations l,
  ) => Stack(
    children: [
      Positioned.fill(
        child: state.conversation.messages.isEmpty
            ? _AgentEmptyState(
                connected: state.connected,
                connecting:
                    state.connection == AgentConnectionStatus.connecting,
                onRetry: _reconnect,
              )
            : Focus(
                focusNode: _transcriptFocus,
                onKeyEvent: _handleTranscriptKey,
                child: Listener(
                  onPointerDown: (_) => _transcriptFocus.requestFocus(),
                  onPointerSignal: _handlePointerSignal,
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: _handleUserScroll,
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      itemCount:
                          state.conversation.messages.length +
                          (state.conversation.error == null ? 0 : 1),
                      findChildIndexCallback: (key) =>
                          _conversationChildIndex(key, state.conversation),
                      itemBuilder: (context, index) {
                        final itemCount =
                            state.conversation.messages.length +
                            (state.conversation.error == null ? 0 : 1);
                        final logicalIndex = itemCount - index - 1;
                        if (logicalIndex < state.conversation.messages.length) {
                          final message =
                              state.conversation.messages[logicalIndex];
                          return AgentMessageView(
                            key: ValueKey('agent-message-${message.id}'),
                            message: message,
                            running: state.conversation.running,
                            waitingForModel:
                                state.conversation.waitingForModel &&
                                logicalIndex ==
                                    state.conversation.messages.length - 1,
                          );
                        }
                        return Padding(
                          key: const ValueKey('agent-conversation-error'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            state.conversation.error!,
                            style: TextStyle(color: context.colors.danger),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
      if (!_isAtBottom && state.conversation.messages.isNotEmpty)
        Positioned(
          right: 16,
          bottom: 12,
          child: FloatingActionButton.small(
            key: const Key('agent-scroll-to-bottom'),
            heroTag: null,
            tooltip: l.tr('agent.scrollToBottom'),
            elevation: 3,
            backgroundColor: context.colors.card,
            foregroundColor: context.colors.primary,
            shape: CircleBorder(side: BorderSide(color: context.colors.border)),
            onPressed: _scrollToBottom,
            child: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
        ),
    ],
  );

  Widget _buildHeader(BuildContext context, AgentState state) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l.tr('agent.history'),
            onPressed: () => _showHistory(context),
            icon: const Icon(Icons.history),
          ),
          Expanded(
            child: Text(
              state.conversation.title.isEmpty
                  ? l.tr('agent.title')
                  : state.conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
            ),
          ),
          if (!state.connected)
            TextButton.icon(
              onPressed: state.connection == AgentConnectionStatus.connecting
                  ? null
                  : _reconnect,
              icon: state.connection == AgentConnectionStatus.connecting
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(
                state.connection == AgentConnectionStatus.connecting
                    ? l.tr('agent.connectingShort')
                    : l.tr('common.retry'),
              ),
            ),
          IconButton(
            tooltip: l.tr('agent.newConversation'),
            onPressed: state.conversation.running
                ? null
                : ref.read(agentControllerProvider.notifier).newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: l.tr('agent.settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AiAgentSettingsPage(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: l.tr('common.close'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  void _send() {
    if (_draft.text.trim().isEmpty) return;
    final error = ref.read(agentControllerProvider.notifier).send(_draft.text);
    if (error == null) {
      _draft.clear();
      _scrollToBottom();
      return;
    }
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.tr(error))));
  }

  void _scrollToBottom() {
    _scrollMode = _AgentScrollMode.pinned;
    if (!_isAtBottom && mounted) setState(() => _isAtBottom = true);
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom() {
    if (_scrollMode != _AgentScrollMode.pinned) return;
    if (_scrollingToBottom) return;
    _scrollingToBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _scrollMode != _AgentScrollMode.pinned) {
        _scrollingToBottom = false;
        return;
      }
      final position = _scroll.position;
      if (position.pixels != position.minScrollExtent) {
        _scroll.jumpTo(position.minScrollExtent);
      }
      _scrollingToBottom = false;
      _handleScroll();
    });
  }

  void _handleScroll() {
    if (_scrollingToBottom || !_scroll.hasClients) return;
    final distanceFromBottom = _distanceFromBottom(_scroll.position);
    _scrollMode = distanceFromBottom <= 1
        ? _AgentScrollMode.pinned
        : _AgentScrollMode.detached;
    final isAtBottom =
        _scrollMode == _AgentScrollMode.pinned &&
        distanceFromBottom < AgentUiTokens.scrollBottomThreshold;
    if (isAtBottom != _isAtBottom && mounted) {
      setState(() => _isAtBottom = isAtBottom);
    }
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.reverse) {
      _detachFromBottom();
    }
    return false;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.scrollDelta.dy < 0) {
      _detachFromBottom();
    }
  }

  KeyEventResult _handleTranscriptKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.home ||
        (key == LogicalKeyboardKey.space &&
            HardwareKeyboard.instance.isShiftPressed)) {
      _detachFromBottom();
    }
    return KeyEventResult.ignored;
  }

  void _detachFromBottom() {
    _scrollMode = _AgentScrollMode.detached;
    if (_isAtBottom && mounted) setState(() => _isAtBottom = false);
  }

  Future<void> _showHistory(BuildContext context) async {
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .refreshSessions(reportErrors: true);
    } catch (error) {
      if (context.mounted) _showError(error);
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.card,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.78,
        child: AgentHistorySheet(),
      ),
    );
  }

  Future<void> _reconnect() async {
    try {
      await ref.read(agentControllerProvider.notifier).refreshConnection();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    showAgentError(context, error);
  }
}

int? _conversationChildIndex(Key key, AgentConversationState conversation) {
  if (key is! ValueKey<String>) return null;
  final value = key.value;
  final itemCount =
      conversation.messages.length + (conversation.error == null ? 0 : 1);
  int logicalIndex;
  if (value.startsWith('agent-message-')) {
    final id = value.substring('agent-message-'.length);
    logicalIndex = conversation.messages.indexWhere((item) => item.id == id);
  } else if (value == 'agent-conversation-error' &&
      conversation.error != null) {
    logicalIndex = itemCount - 1;
  } else {
    return null;
  }
  return logicalIndex < 0 ? null : itemCount - logicalIndex - 1;
}

double _distanceFromBottom(ScrollMetrics metrics) =>
    math.max(0.0, metrics.pixels - metrics.minScrollExtent);

String _noticeText(AppLocalizations l, String notice) {
  final parts = notice.split(':');
  return switch (parts.first) {
    'history_repaired' => l.trf('agent.notice.historyRepaired', [parts.last]),
    'compacted' => l.trf('agent.notice.compacted', [parts.last]),
    'pending_approvals' => l.trf('agent.notice.pendingApprovals', [parts.last]),
    'stream_error' => parts.skip(1).join(':'),
    _ => notice,
  };
}

class _AgentNotice extends StatelessWidget {
  const _AgentNotice({
    required this.text,
    required this.color,
    this.actionLabel,
    this.onAction,
    this.onClose,
  });
  final String text;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
    color: color.withValues(alpha: 0.11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: context.colors.text),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}

class _AgentEmptyState extends StatelessWidget {
  const _AgentEmptyState({
    required this.connected,
    required this.connecting,
    required this.onRetry,
  });
  final bool connected;
  final bool connecting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 44,
              color: context.colors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l.tr('agent.empty.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              connected ? l.tr('agent.empty.body') : l.tr('agent.connecting'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted),
            ),
            if (!connected && !connecting) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l.tr('agent.reconnect')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
