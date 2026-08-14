import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reduces streaming reasoning, markdown text and usage', () {
    var state = AgentConversationState(
      messages: [createUserAgentMessage('inspect the host')],
      running: true,
    );

    state = applyAgentEvent(state, const {'type': 'turn_start'});
    state = applyAgentEvent(state, const {
      'type': 'reasoning_delta',
      'text': 'Checking ',
    });
    state = applyAgentEvent(state, const {
      'type': 'reasoning_delta',
      'text': 'safely.',
    });
    state = applyAgentEvent(state, const {
      'type': 'text_delta',
      'text': '**Done**',
    });
    state = applyAgentEvent(state, const {
      'type': 'finish',
      'usage': {'inputTokens': 8, 'outputTokens': 5, 'totalTokens': 13},
    });

    final assistant = state.messages.last;
    expect(assistant.role, AgentMessageRole.assistant);
    expect(assistant.parts, hasLength(2));
    expect(
      (assistant.parts.first as AgentReasoningPart).text,
      'Checking safely.',
    );
    expect((assistant.parts.first as AgentReasoningPart).done, isTrue);
    expect((assistant.parts.last as AgentTextPart).text, '**Done**');
    expect(assistant.usage?.totalTokens, 13);
    expect(state.running, isFalse);
  });

  test('keeps approval received before its tool call and resolves result', () {
    var state = AgentConversationState(
      messages: [createUserAgentMessage('read logs')],
    );
    state = applyAgentEvent(state, const {'type': 'turn_start'});
    state = applyAgentEvent(state, const {
      'type': 'approval_request',
      'requestId': 'approval-1',
      'toolCallId': 'tool-1',
      'tool': 'read_file',
      'input': {'path': '/var/log/app.log'},
      'effect': 'read',
      'targets': ['/var/log/app.log'],
    });
    state = applyAgentEvent(state, const {
      'type': 'tool_call',
      'toolCallId': 'tool-1',
      'tool': 'read_file',
      'input': {'path': '/var/log/app.log'},
    });

    var tool = state.messages.last.parts.single as AgentToolPart;
    expect(tool.status, AgentToolStatus.awaitingApproval);
    expect(state.pendingApprovals.single.requestId, 'approval-1');

    state = removeAgentApproval(state, 'approval-1');
    state = applyAgentEvent(state, const {
      'type': 'tool_result',
      'toolCallId': 'tool-1',
      'output': {'type': 'text', 'value': 'ok'},
    });
    tool = state.messages.last.parts.single as AgentToolPart;
    expect(tool.status, AgentToolStatus.done);
    expect(tool.output, 'ok');
    expect(state.pendingApprovals, isEmpty);
  });

  test('marks a Plus-restricted tool as denied instead of running forever', () {
    var state = AgentConversationState(
      messages: [createUserAgentMessage('restart service')],
    );
    state = applyAgentEvent(state, const {'type': 'turn_start'});
    state = applyAgentEvent(state, const {
      'type': 'tool_call',
      'toolCallId': 'tool-plus',
      'tool': 'exec_command',
      'input': {'command': 'systemctl restart app'},
    });
    state = applyAgentEvent(state, const {
      'type': 'tool_requires_plus',
      'toolCallId': 'tool-plus',
      'message': 'Plus required',
    });

    var tool = state.messages.last.parts.single as AgentToolPart;
    expect(tool.status, AgentToolStatus.denied);
    expect(tool.error, 'Plus required');
    expect(state.plusRequired, 'Plus required');

    state = applyAgentEvent(state, const {
      'type': 'tool_result',
      'toolCallId': 'tool-plus',
      'error': 'Plus required',
    });
    state = applyAgentEvent(state, const {'type': 'finish'});
    tool = state.messages.last.parts.single as AgentToolPart;
    expect(tool.status, AgentToolStatus.denied);
    expect(state.running, isFalse);
  });

  test('finish closes any tool call that never returned a result', () {
    var state = AgentConversationState(
      messages: [createUserAgentMessage('run operation')],
    );
    state = applyAgentEvent(state, const {'type': 'turn_start'});
    state = applyAgentEvent(state, const {
      'type': 'tool_call',
      'toolCallId': 'tool-unfinished',
      'tool': 'exec_command',
      'input': {'command': 'true'},
    });

    state = applyAgentEvent(state, const {'type': 'finish'});

    final tool = state.messages.last.parts.single as AgentToolPart;
    expect(tool.status, AgentToolStatus.error);
    expect(tool.error, 'tool_incomplete');
    expect(state.running, isFalse);
  });

  test('restores persisted tools, results and per-turn usage', () {
    final session = AgentSession.fromJson({
      'id': 'session-1',
      'title': 'Host check',
      'scope': 'ops',
      'modelId': 'model-a',
      'permission': 'review',
      'hostIds': ['host-1'],
      'messages': [
        {'role': 'user', 'content': 'check disk'},
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool-call',
              'toolCallId': 'tool-1',
              'toolName': 'get_server_status',
              'input': {'hostId': 'host-1'},
            },
          ],
        },
        {
          'role': 'tool',
          'content': [
            {
              'type': 'tool-result',
              'toolCallId': 'tool-1',
              'output': {
                'type': 'json',
                'value': {'disk': 42},
              },
            },
          ],
        },
      ],
      'toolMeta': {
        'tool-1': {'durationMs': 35, 'approved': true},
      },
      'turnMeta': [
        {
          'usage': {'totalTokens': 21},
        },
      ],
      'usage': {'totalTokens': 21},
    });

    final conversation = conversationFromSession(session);
    final assistant = conversation.messages.last;
    final tool = assistant.parts.single as AgentToolPart;
    expect(conversation.sessionId, 'session-1');
    expect(tool.status, AgentToolStatus.done);
    expect(tool.output, {'disk': 42});
    expect(tool.durationMs, 35);
    expect(assistant.usage?.totalTokens, 21);
  });

  test('merges historical assistant steps into one rendered turn', () {
    final session = AgentSession.fromJson({
      'id': 'session-merged-turn',
      'title': 'Status check',
      'scope': 'ops',
      'modelId': 'model-a',
      'permission': 'review',
      'hostIds': ['host-1'],
      'messages': [
        {'role': 'user', 'content': 'check status'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'reasoning', 'text': 'Selecting a tool'},
            {
              'type': 'tool-call',
              'toolCallId': 'tool-merge',
              'toolName': 'host_status',
              'input': {'hostId': 'host-1'},
            },
          ],
        },
        {
          'role': 'tool',
          'content': [
            {
              'type': 'tool-result',
              'toolCallId': 'tool-merge',
              'output': {'type': 'text', 'value': 'online'},
            },
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'reasoning', 'text': 'Summarizing'},
            {'type': 'text', 'text': 'The host is online.'},
          ],
        },
      ],
      'turnMeta': [
        {
          'usage': {'totalTokens': 12},
        },
      ],
    });

    final messages = messagesFromAgentSession(session);

    expect(messages, hasLength(2));
    final assistant = messages.last;
    expect(assistant.role, AgentMessageRole.assistant);
    expect(assistant.parts, hasLength(4));
    expect(
      assistant.parts.whereType<AgentToolPart>().single.status,
      AgentToolStatus.done,
    );
    expect(assistant.text, contains('The host is online.'));
    expect(assistant.sourceIndex, 3);
    expect(assistant.usage?.totalTokens, 12);
  });

  test('historical tool calls without results are finalized', () {
    final session = AgentSession.fromJson({
      'id': 'session-unfinished-tool',
      'title': 'Interrupted tool',
      'scope': 'ops',
      'modelId': 'model-a',
      'permission': 'review',
      'hostIds': ['host-1'],
      'messages': [
        {'role': 'user', 'content': 'restart service'},
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool-call',
              'toolCallId': 'tool-history-unfinished',
              'toolName': 'exec_command',
              'input': {'command': 'systemctl restart app'},
            },
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'The operation could not be executed.'},
          ],
        },
      ],
      'turnMeta': [
        {
          'usage': {'totalTokens': 9},
        },
      ],
    });

    final tool = messagesFromAgentSession(
      session,
    ).last.parts.whereType<AgentToolPart>().single;
    expect(tool.status, AgentToolStatus.error);
    expect(tool.error, 'tool_incomplete');
  });

  test('finds stable edit and branch turn indexes', () {
    final first = createUserAgentMessage('one');
    final answer = AgentMessage(
      id: 'answer',
      role: AgentMessageRole.assistant,
      parts: const [AgentTextPart('result')],
      createdAt: 1,
    );
    final second = createUserAgentMessage('two');
    final messages = [first, answer, second];

    expect(userTurnIndex(messages, first.id), 0);
    expect(userTurnIndex(messages, second.id), 1);
    expect(previousUserMessage(messages, answer.id)?.id, first.id);
  });
}
