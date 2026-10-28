import 'package:easynode_native/features/ai_agent/agent_controller.dart';
import 'package:easynode_native/features/ai_agent/agent_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent option fallback', () {
    test('keeps a current model that still exists', () {
      expect(
        resolveAgentModel(
          models: const ['model-a', 'model-b'],
          currentModel: 'model-b',
          defaultModel: 'model-a',
        ),
        'model-b',
      );
    });

    test('uses a valid default and otherwise the first configured model', () {
      expect(
        resolveAgentModel(
          models: const ['model-a', 'model-b'],
          currentModel: 'removed-model',
          defaultModel: 'model-b',
        ),
        'model-b',
      );
      expect(
        resolveAgentModel(
          models: const ['model-a', 'model-b'],
          currentModel: 'removed-model',
          defaultModel: 'stale-default',
        ),
        'model-a',
      );
    });

    test('keeps valid history mode and rejects unknown modes', () {
      expect(resolveAgentMode('authorized'), 'authorized');
      expect(resolveAgentMode('legacy'), 'assist');
      expect(resolveAgentMode('review'), 'assist');
      expect(resolveAgentMode('full_access'), 'full_access');
      expect(const AgentState().mode, 'assist');
      expect(const AgentState().presets.map((p) => p.key), [
        'assist',
        'authorized',
        'full_access',
      ]);
    });
  });

  test('empty drafts are silently unavailable for sending', () {
    const state = AgentState(connection: AgentConnectionStatus.connected);

    expect(state.canSendDraft(''), isFalse);
    expect(state.canSendDraft('   \n'), isFalse);
    expect(state.canSendDraft('hello'), isTrue);
  });
}
