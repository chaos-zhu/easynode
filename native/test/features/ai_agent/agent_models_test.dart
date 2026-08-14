import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old server config defaults the native entry to enabled', () {
    final config = AgentProviderConfig.fromJson({
      'providerType': 'openai-compatible',
      'models': ['model-a'],
      'ui': {'petEnabled': false},
    });

    expect(config.nativeAgentEnabled, isTrue);
  });

  test('provider serialization preserves unrelated UI preferences', () {
    final config =
        AgentProviderConfig.fromJson({
          '_id': 'database-id',
          'providerType': 'openai-compatible',
          'apiUrl': 'https://old.example/v1',
          'apiKey': 'old-key',
          'models': ['old-model'],
          'ui': {'petEnabled': false, 'theme': 'robot'},
        }).copyWith(
          apiUrl: 'https://new.example/v1',
          apiKey: 'new-key',
          models: ['new-model'],
          nativeAgentEnabled: false,
        );

    final json = config.toProviderJson();
    expect(json, isNot(contains('_id')));
    expect(json['apiUrl'], 'https://new.example/v1');
    expect(json['models'], ['new-model']);
    expect(json['ui'], {
      'petEnabled': false,
      'theme': 'robot',
      'nativeAgentEnabled': false,
    });
  });

  test('provider bounds unsafe iteration and context values', () {
    final config = AgentProviderConfig.fromJson({
      'contextLimit': 1,
      'maxSteps': 500,
    });

    expect(config.contextLimit, 1024);
    expect(config.maxSteps, 50);
  });
}
