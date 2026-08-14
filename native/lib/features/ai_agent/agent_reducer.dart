import 'agent_models.dart';

const _unfinishedToolReason = 'tool_incomplete';

class AgentConversationState {
  const AgentConversationState({
    this.sessionId = '',
    this.title = '',
    this.messages = const [],
    this.pendingApprovals = const [],
    this.usage = const AgentUsage(),
    this.turnUsage = const AgentUsage(),
    this.running = false,
    this.waitingForModel = false,
    this.aborted = false,
    this.error,
    this.notice,
    this.plusRequired,
    this.policy,
    this.clamped,
  });

  final String sessionId;
  final String title;
  final List<AgentMessage> messages;
  final List<AgentApproval> pendingApprovals;
  final AgentUsage usage;
  final AgentUsage turnUsage;
  final bool running;
  final bool waitingForModel;
  final bool aborted;
  final String? error;
  final String? notice;
  final String? plusRequired;
  final Map<String, dynamic>? policy;
  final Map<String, dynamic>? clamped;

  AgentConversationState copyWith({
    String? sessionId,
    String? title,
    List<AgentMessage>? messages,
    List<AgentApproval>? pendingApprovals,
    AgentUsage? usage,
    AgentUsage? turnUsage,
    bool? running,
    bool? waitingForModel,
    bool? aborted,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    String? plusRequired,
    bool clearPlusRequired = false,
    Map<String, dynamic>? policy,
    Map<String, dynamic>? clamped,
  }) => AgentConversationState(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    usage: usage ?? this.usage,
    turnUsage: turnUsage ?? this.turnUsage,
    running: running ?? this.running,
    waitingForModel: waitingForModel ?? this.waitingForModel,
    aborted: aborted ?? this.aborted,
    error: clearError ? null : error ?? this.error,
    notice: clearNotice ? null : notice ?? this.notice,
    plusRequired: clearPlusRequired ? null : plusRequired ?? this.plusRequired,
    policy: policy ?? this.policy,
    clamped: clamped ?? this.clamped,
  );

  static const empty = AgentConversationState();
}

int _sequence = 0;
String _nextId(String prefix) =>
    '$prefix-${DateTime.now().millisecondsSinceEpoch}-${_sequence++}';

AgentMessage createUserAgentMessage(String text) => AgentMessage(
  id: _nextId('u'),
  role: AgentMessageRole.user,
  parts: [AgentTextPart(text)],
  createdAt: DateTime.now().millisecondsSinceEpoch,
);

AgentMessage _createAssistantMessage() => AgentMessage(
  id: _nextId('a'),
  role: AgentMessageRole.assistant,
  parts: const [],
  createdAt: DateTime.now().millisecondsSinceEpoch,
);

AgentConversationState applyAgentEvent(
  AgentConversationState state,
  Map<String, dynamic> event,
) {
  final type = event['type']?.toString() ?? '';
  switch (type) {
    case 'session_created':
      final session = stringMap(event['session']);
      return state.copyWith(
        sessionId: session['id']?.toString() ?? state.sessionId,
        title: session['title']?.toString() ?? state.title,
      );
    case 'session_saved':
      final session = stringMap(event['session']);
      return state.copyWith(
        title: session['title']?.toString() ?? state.title,
        usage: session.containsKey('usage')
            ? AgentUsage.fromJson(session['usage'])
            : state.usage,
        turnUsage: session.containsKey('usage')
            ? const AgentUsage()
            : state.turnUsage,
      );
    case 'history_repaired':
      return state.copyWith(
        notice: 'history_repaired:${intValue(event['count'])}',
      );
    case 'compacted':
      return state.copyWith(
        notice:
            'compacted:${event['degraded'] == true ? 1 : 0}:${intValue(event['droppedCount'])}',
      );
    case 'pending_approvals':
      final count = event['items'] is List
          ? (event['items'] as List).length
          : 0;
      return count > 0
          ? state.copyWith(notice: 'pending_approvals:$count')
          : state;
    case 'tool_requires_plus':
      final reason = event['message']?.toString() ?? 'plus_required';
      final updated = _updateTool(
        state,
        event['toolCallId']?.toString() ?? '',
        (part) => part.copyWith(status: AgentToolStatus.denied, error: reason),
      );
      return updated.copyWith(plusRequired: reason);
    case 'turn_start':
      return state.copyWith(
        running: true,
        waitingForModel: false,
        aborted: false,
        clearError: true,
        turnUsage: const AgentUsage(),
        policy: stringMap(event['policy']),
        clamped: stringMap(event['clamped']),
        messages: [...state.messages, _createAssistantMessage()],
      );
    case 'text_delta':
      return _appendStreamText(state, event['text']?.toString() ?? '', false);
    case 'reasoning_delta':
      return _appendStreamText(state, event['text']?.toString() ?? '', true);
    case 'tool_call':
      return _appendTool(state, event);
    case 'tool_progress':
      return _updateTool(
        state,
        event['toolCallId']?.toString() ?? '',
        (part) => part.copyWith(durationMs: intValue(event['durationMs'])),
      );
    case 'tool_result':
      return _updateTool(
        state,
        event['toolCallId']?.toString() ?? '',
        (part) => event['error'] != null
            ? part.copyWith(
                status: part.status == AgentToolStatus.denied
                    ? AgentToolStatus.denied
                    : AgentToolStatus.error,
                error: event['error'].toString(),
              )
            : part.copyWith(
                status: AgentToolStatus.done,
                output: normalizeAgentToolOutput(event['output']),
                clearError: true,
              ),
      );
    case 'awaiting_model':
      return state.copyWith(waitingForModel: true);
    case 'model_resumed':
      return state.copyWith(waitingForModel: false);
    case 'tool_denied':
      return _updateTool(
        state,
        event['toolCallId']?.toString() ?? '',
        (part) => part.copyWith(
          status: AgentToolStatus.denied,
          error: event['reason']?.toString() ?? '',
          risk: event['permanent'] == true
              ? {
                  'level': 'deny',
                  'reason': event['reason'],
                  'category': event['category'],
                }
              : null,
        ),
      );
    case 'approval_request':
      final approval = AgentApproval.fromEvent(event);
      final updated = _updateTool(
        state,
        approval.toolCallId,
        (part) => part.copyWith(
          status: AgentToolStatus.awaitingApproval,
          risk: approval.risk,
        ),
      );
      return updated.copyWith(
        pendingApprovals: [
          ...updated.pendingApprovals.where(
            (item) => item.requestId != approval.requestId,
          ),
          approval,
        ],
      );
    case 'approval_timeout':
    case 'approval_cancelled':
      return removeAgentApproval(state, event['requestId']?.toString() ?? '');
    case 'step_finish':
      return state.copyWith(
        turnUsage: state.turnUsage.add(AgentUsage.fromJson(event['usage'])),
      );
    case 'finish':
      final usage = AgentUsage.fromJson(event['usage']);
      return _applyUsageToLastAssistant(
        _finishUnresolvedTools(
          state.copyWith(
            running: false,
            waitingForModel: false,
            turnUsage: usage,
            pendingApprovals: const [],
          ),
          _unfinishedToolReason,
        ),
        usage,
      );
    case 'aborted':
      return _finishUnresolvedTools(
        state.copyWith(running: false, waitingForModel: false, aborted: true),
        'aborted',
      );
    case 'stopped':
      return _finishUnresolvedTools(
        state.copyWith(
          running: false,
          waitingForModel: false,
          pendingApprovals: const [],
        ),
        'stopped',
      );
    case 'error':
      return _finishUnresolvedTools(
        state.copyWith(
          running: false,
          waitingForModel: false,
          error: event['message']?.toString() ?? 'Unknown error',
        ),
        event['message']?.toString() ?? 'Unknown error',
      );
    case 'stream_error':
      return state.copyWith(notice: 'stream_error:${event['message'] ?? ''}');
    default:
      return state;
  }
}

AgentConversationState removeAgentApproval(
  AgentConversationState state,
  String requestId,
) => state.copyWith(
  pendingApprovals: state.pendingApprovals
      .where((item) => item.requestId != requestId)
      .toList(growable: false),
);

AgentConversationState _appendStreamText(
  AgentConversationState state,
  String text,
  bool reasoning,
) {
  if (text.isEmpty || state.messages.isEmpty) return state;
  final messages = [...state.messages];
  final message = messages.last;
  final parts = [...message.parts];
  if (!reasoning && parts.lastOrNull is AgentReasoningPart) {
    final previous = parts.last as AgentReasoningPart;
    parts[parts.length - 1] = AgentReasoningPart(previous.text, done: true);
  }
  final last = parts.lastOrNull;
  if (reasoning && last is AgentReasoningPart && !last.done) {
    parts[parts.length - 1] = AgentReasoningPart('${last.text}$text');
  } else if (!reasoning && last is AgentTextPart) {
    parts[parts.length - 1] = AgentTextPart('${last.text}$text');
  } else {
    parts.add(reasoning ? AgentReasoningPart(text) : AgentTextPart(text));
  }
  messages[messages.length - 1] = message.copyWith(parts: parts);
  return state.copyWith(messages: messages, waitingForModel: false);
}

AgentConversationState _appendTool(
  AgentConversationState state,
  Map<String, dynamic> event,
) {
  if (state.messages.isEmpty) return state;
  final messages = [...state.messages];
  final message = messages.last;
  final parts = [...message.parts];
  if (parts.lastOrNull is AgentReasoningPart) {
    final reasoning = parts.last as AgentReasoningPart;
    parts[parts.length - 1] = AgentReasoningPart(reasoning.text, done: true);
  }
  final toolCallId = event['toolCallId']?.toString() ?? '';
  final pending = state.pendingApprovals
      .where((item) => item.toolCallId == toolCallId)
      .firstOrNull;
  parts.add(
    AgentToolPart(
      toolCallId: toolCallId,
      tool: event['tool']?.toString() ?? '',
      input: stringMap(event['input']),
      status: pending == null
          ? AgentToolStatus.running
          : AgentToolStatus.awaitingApproval,
      risk: pending?.risk,
    ),
  );
  messages[messages.length - 1] = message.copyWith(parts: parts);
  return state.copyWith(messages: messages, waitingForModel: false);
}

AgentConversationState _updateTool(
  AgentConversationState state,
  String toolCallId,
  AgentToolPart Function(AgentToolPart part) update,
) {
  if (toolCallId.isEmpty) return state;
  final messages = [...state.messages];
  for (
    var messageIndex = messages.length - 1;
    messageIndex >= 0;
    messageIndex--
  ) {
    final parts = [...messages[messageIndex].parts];
    final partIndex = parts.indexWhere(
      (part) => part is AgentToolPart && part.toolCallId == toolCallId,
    );
    if (partIndex < 0) continue;
    parts[partIndex] = update(parts[partIndex] as AgentToolPart);
    messages[messageIndex] = messages[messageIndex].copyWith(parts: parts);
    return state.copyWith(messages: messages);
  }
  return state;
}

AgentConversationState _applyUsageToLastAssistant(
  AgentConversationState state,
  AgentUsage usage,
) {
  final messages = [...state.messages];
  for (var index = messages.length - 1; index >= 0; index--) {
    if (messages[index].role == AgentMessageRole.assistant) {
      messages[index] = messages[index].copyWith(usage: usage);
      break;
    }
  }
  return state.copyWith(messages: messages);
}

AgentConversationState _finishUnresolvedTools(
  AgentConversationState state,
  String reason,
) => state.copyWith(
  messages: _finishUnresolvedToolMessages(state.messages, reason),
);

List<AgentMessage> _finishUnresolvedToolMessages(
  List<AgentMessage> messages,
  String reason,
) => messages
    .map((message) {
      final parts = message.parts
          .map((part) {
            if (part is! AgentToolPart) return part;
            if (part.status != AgentToolStatus.running &&
                part.status != AgentToolStatus.awaitingApproval) {
              return part;
            }
            return part.copyWith(status: AgentToolStatus.error, error: reason);
          })
          .toList(growable: false);
      return message.copyWith(parts: parts);
    })
    .toList(growable: false);

Object? normalizeAgentToolOutput(Object? output) {
  if (output is! Map) return output;
  final json = stringMap(output);
  if (json['type'] is String && json.containsKey('value')) {
    if ((json['type'] as String).startsWith('error')) {
      return {'__error': true, 'value': json['value']};
    }
    return json['value'];
  }
  return output;
}

AgentConversationState conversationFromSession(AgentSession session) =>
    AgentConversationState(
      sessionId: session.id,
      title: session.title,
      messages: messagesFromAgentSession(session),
      usage: session.usage,
    );

List<AgentMessage> messagesFromAgentSession(AgentSession session) {
  final messages = <AgentMessage>[];
  final toolParts = <String, AgentToolPart>{};
  var turnIndex = 0;
  AgentMessage? lastAssistant;

  void sealUsage() {
    if (lastAssistant == null || turnIndex == 0) return;
    final usage = AgentUsage.fromJson(
      turnIndex - 1 < session.turnMeta.length
          ? session.turnMeta[turnIndex - 1]['usage']
          : null,
    );
    final index = messages.indexWhere((item) => item.id == lastAssistant!.id);
    if (index >= 0) messages[index] = messages[index].copyWith(usage: usage);
    lastAssistant = null;
  }

  for (
    var sourceIndex = 0;
    sourceIndex < session.messages.length;
    sourceIndex++
  ) {
    final raw = session.messages[sourceIndex];
    final role = raw['role']?.toString();
    final content = _contentParts(raw['content']);
    if (role == 'user') {
      sealUsage();
      final meta = turnIndex < session.turnMeta.length
          ? session.turnMeta[turnIndex]
          : const <String, dynamic>{};
      messages.add(
        AgentMessage(
          id: _nextId('u'),
          role: AgentMessageRole.user,
          parts: [AgentTextPart(_joinText(content))],
          createdAt: intValue(meta['createdAt']),
        ),
      );
      turnIndex++;
      continue;
    }
    if (role == 'assistant') {
      final parts = <AgentMessagePart>[];
      for (final part in content) {
        switch (part['type']?.toString()) {
          case 'text':
            final text = part['text']?.toString() ?? '';
            if (text.isNotEmpty) parts.add(AgentTextPart(text));
            break;
          case 'reasoning':
            final text = part['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              parts.add(AgentReasoningPart(text, done: true));
            }
            break;
          case 'tool-call':
            final id = part['toolCallId']?.toString() ?? '';
            final meta = stringMap(session.toolMeta[id]);
            final tool = AgentToolPart(
              toolCallId: id,
              tool: part['toolName']?.toString() ?? '',
              input: stringMap(part['input']),
              status: meta['denied'] == true
                  ? AgentToolStatus.denied
                  : AgentToolStatus.running,
              durationMs: meta['durationMs'] == null
                  ? null
                  : intValue(meta['durationMs']),
              risk: meta['risk'] != null && meta['risk'] != 'normal'
                  ? {
                      'level': meta['risk'],
                      'reason': meta['riskReason'],
                      'category': meta['riskCategory'],
                    }
                  : null,
              approval: meta['approved'] == null
                  ? null
                  : {
                      'approved': meta['approved'],
                      'scope': meta['approvalScope'],
                      'cached': meta['approvalCached'],
                    },
            );
            parts.add(tool);
            toolParts[id] = tool;
            break;
        }
      }
      if (parts.isNotEmpty) {
        final previous = lastAssistant;
        if (previous == null) {
          final message = AgentMessage(
            id: _nextId('a'),
            role: AgentMessageRole.assistant,
            parts: parts,
            createdAt: 0,
            sourceIndex: sourceIndex,
          );
          messages.add(message);
          lastAssistant = message;
        } else {
          final messageIndex = messages.indexWhere(
            (item) => item.id == previous.id,
          );
          final merged = AgentMessage(
            id: previous.id,
            role: AgentMessageRole.assistant,
            parts: [...previous.parts, ...parts],
            createdAt: previous.createdAt,
            sourceIndex: sourceIndex,
            usage: previous.usage,
          );
          if (messageIndex >= 0) messages[messageIndex] = merged;
          lastAssistant = merged;
        }
      }
      continue;
    }
    if (role == 'tool') {
      for (final result in content) {
        if (result['type'] != 'tool-result') continue;
        final id = result['toolCallId']?.toString() ?? '';
        final original = toolParts[id];
        if (original == null) continue;
        final normalized = normalizeAgentToolOutput(result['output']);
        final isError = normalized is Map && normalized['__error'] == true;
        final updated = isError
            ? original.copyWith(
                status: original.status == AgentToolStatus.denied
                    ? AgentToolStatus.denied
                    : AgentToolStatus.error,
                error: normalized['value']?.toString() ?? '',
              )
            : original.copyWith(
                status: original.status == AgentToolStatus.denied
                    ? AgentToolStatus.denied
                    : AgentToolStatus.done,
                output: normalized,
              );
        toolParts[id] = updated;
        for (
          var messageIndex = messages.length - 1;
          messageIndex >= 0;
          messageIndex--
        ) {
          final parts = [...messages[messageIndex].parts];
          final index = parts.indexWhere(
            (part) => part is AgentToolPart && part.toolCallId == id,
          );
          if (index < 0) continue;
          parts[index] = updated;
          final updatedMessage = messages[messageIndex].copyWith(parts: parts);
          messages[messageIndex] = updatedMessage;
          if (lastAssistant?.id == updatedMessage.id) {
            lastAssistant = updatedMessage;
          }
          break;
        }
      }
    }
  }
  sealUsage();
  return _finishUnresolvedToolMessages(messages, _unfinishedToolReason);
}

List<Map<String, dynamic>> _contentParts(Object? content) {
  if (content is List) return mapList(content);
  if (content == null) return const [];
  return [
    {'type': 'text', 'text': content.toString()},
  ];
}

String _joinText(List<Map<String, dynamic>> content) => content
    .where((part) => part['type'] == 'text')
    .map((part) => part['text']?.toString() ?? '')
    .join();

int userTurnIndex(List<AgentMessage> messages, String messageId) {
  var turn = -1;
  for (final message in messages) {
    if (message.role == AgentMessageRole.user) turn++;
    if (message.id == messageId) return turn;
  }
  return -1;
}

AgentMessage? previousUserMessage(
  List<AgentMessage> messages,
  String messageId,
) {
  final target = messages.indexWhere((message) => message.id == messageId);
  for (var index = target - 1; index >= 0; index--) {
    if (messages[index].role == AgentMessageRole.user) return messages[index];
  }
  return null;
}
