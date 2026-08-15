import 'package:easynode_native/features/servers/server_credential_model.dart';
import 'package:easynode_native/features/servers/server_group_model.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_proxy_model.dart';
import 'package:easynode_native/features/settings/models/plus_info.dart';
import 'package:easynode_native/state/credential_list_notifier.dart';
import 'package:easynode_native/state/group_list_notifier.dart';
import 'package:easynode_native/state/host_list_notifier.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:easynode_native/state/proxy_list_notifier.dart';
import 'package:easynode_native/state/server_data_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _HostFixture extends HostListNotifier {
  int builds = 0;

  @override
  Future<List<ServerModel>> build() async {
    builds++;
    return const [];
  }
}

class _GroupFixture extends GroupListNotifier {
  int builds = 0;

  @override
  Future<List<ServerGroupModel>> build() async {
    builds++;
    return const [];
  }
}

class _CredentialFixture extends CredentialListNotifier {
  int builds = 0;

  @override
  Future<List<ServerCredentialModel>> build() async {
    builds++;
    return const [];
  }
}

class _ProxyFixture extends ProxyListNotifier {
  int builds = 0;

  @override
  Future<List<ServerProxyModel>> build() async {
    builds++;
    return const [];
  }
}

class _PlusFixture extends PlusInfoNotifier {
  int builds = 0;

  @override
  Future<PlusInfo> build() async {
    builds++;
    return PlusInfo.empty();
  }
}

void main() {
  test('server bootstrap starts every shared provider only once', () async {
    final hosts = _HostFixture();
    final groups = _GroupFixture();
    final credentials = _CredentialFixture();
    final proxies = _ProxyFixture();
    final plus = _PlusFixture();
    final container = ProviderContainer(
      overrides: [
        hostListProvider.overrideWith(() => hosts),
        groupListProvider.overrideWith(() => groups),
        credentialListProvider.overrideWith(() => credentials),
        proxyListProvider.overrideWith(() => proxies),
        plusInfoProvider.overrideWith(() => plus),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serverSharedDataBootstrapProvider.future);
    await container.read(serverSharedDataBootstrapProvider.future);

    expect(hosts.builds, 1);
    expect(groups.builds, 1);
    expect(credentials.builds, 1);
    expect(proxies.builds, 1);
    expect(plus.builds, 1);
  });
}
