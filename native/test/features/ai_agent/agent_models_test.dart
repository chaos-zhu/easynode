import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('target host metadata is optional and has readable fallbacks', () {
    for (final value in [null, 'invalid', <String, dynamic>{}]) {
      expect(AgentTargetHost.fromJson(value), isNull);
    }
    final target = AgentTargetHost.fromJson({
      'hostId': 'host-1',
      'name': ' Production ',
      'address': '10.0.0.1:22',
    })!;
    expect(target.hostId, 'host-1');
    expect(target.label, 'Production · 10.0.0.1:22');
    expect(
      AgentTargetHost.fromJson({'address': '10.0.0.1'})!.label,
      '10.0.0.1',
    );
    expect(AgentTargetHost.fromJson({'hostId': 'host-1'})!.label, 'host-1');
    const part = AgentToolPart(
      toolCallId: 'tool-1',
      tool: 'read_file',
      input: {},
    );
    expect(
      part.copyWith(targetHost: target).copyWith(durationMs: 10).targetHost,
      same(target),
    );
  });

  test('approval accepts resolved target and keeps legacy host name', () {
    final legacy = AgentApproval.fromEvent({'hostName': 'Legacy host'});
    expect(legacy.hostName, 'Legacy host');
    expect(legacy.targetHost, isNull);
    final approval = AgentApproval.fromEvent({
      'hostName': 'Legacy host',
      'targetHost': {
        'hostId': 'host-1',
        'name': 'Production',
        'address': '10.0.0.1:22',
      },
    });
    expect(approval.targetHost?.label, 'Production · 10.0.0.1:22');
  });

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
