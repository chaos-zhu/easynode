import 'package:easynode_native/features/ai_agent/agent_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconnect backoff is bounded', () {
    expect(agentReconnectDelay(0), const Duration(seconds: 2));
    expect(agentReconnectDelay(1), const Duration(seconds: 5));
    expect(agentReconnectDelay(2), const Duration(seconds: 10));
    expect(agentReconnectDelay(100), const Duration(seconds: 10));
  });

  test('native run payload is always ops-only and context-free', () {
    final hosts = ['host-1'];
    final payload = buildOpsAgentRunPayload(
      sessionId: 'session-1',
      input: '  inspect services  ',
      modelId: 'model-a',
      permission: 'review',
      hostIds: hosts,
    );
    hosts.add('host-2');

    expect(payload, {
      'sessionId': 'session-1',
      'input': 'inspect services',
      'modelId': 'model-a',
      'permission': 'review',
      'hostIds': ['host-1'],
      'scope': 'ops',
    });
    expect(payload, isNot(contains('terminalContext')));
    expect(payload, isNot(contains('terminalPermission')));
    expect(payload, isNot(contains('hostId')));
  });
}
