import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:easynode_native/state/host_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _HostListFixture extends HostListNotifier {
  @override
  Future<List<ServerModel>> build() async => [
    ServerModel.fromJson({
      'id': 'host-1',
      'name': 'Production',
      'host': '10.0.0.8',
      'port': 2222,
      'aiPolicy': {'enabled': false, 'maxEffect': 'read', 'maxMode': 'review'},
    }),
  ];
}

void main() {
  test('agent host policies are derived from the shared host list', () async {
    final container = ProviderContainer(
      overrides: [hostListProvider.overrideWith(_HostListFixture.new)],
    );
    addTearDown(container.dispose);

    await container.read(hostListProvider.future);
    final policies = container.read(agentHostPoliciesProvider);

    expect(policies, hasLength(1));
    expect(policies.single.hostId, 'host-1');
    expect(policies.single.name, 'Production');
    expect(policies.single.address, '10.0.0.8:2222');
    expect(policies.single.enabled, isFalse);
    expect(policies.single.maxEffect, 'read');
    expect(policies.single.maxMode, 'review');
  });
}
