import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_model.dart';
import 'package:mobile/features/servers/server_repository.dart';
import 'package:mobile/features/servers/servers_tab.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';
import 'package:mobile/state/api_providers.dart';
import 'package:mobile/state/host_list_notifier.dart';

class _FakeRepository implements ServerRepository {
  _FakeRepository({
    this.hosts = const [],
    this.fetchError,
    SshConnectionConfig? config,
    this.sshError,
  }) : config = config ?? _defaultConfig;

  List<ServerModel> hosts;
  Object? fetchError;
  SshConnectionConfig config;
  Object? sshError;
  int connectCalls = 0;

  static const _defaultConfig = SshConnectionConfig(
    hostId: 'h1',
    name: 'srv',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'pwd',
    privateKey: '',
    passphrase: '',
  );

  @override
  Future<List<ServerModel>> fetchHosts() async {
    if (fetchError != null) throw fetchError!;
    return hosts;
  }

  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    connectCalls++;
    if (sshError != null) throw sshError!;
    return config;
  }
}

ServerModel _server({String id = 'h1', bool canConnect = true}) {
  return ServerModel.fromJson({
    'id': id,
    'name': 'srv-$id',
    'host': '10.0.0.2',
    'port': 22,
    'username': 'root',
    'authType': 'password',
    'group': '',
    'tag': const [],
    'expired': !canConnect,
    'isConfig': canConnect,
  });
}

Widget _wrap({required ServerRepository repo}) {
  return ProviderScope(
    overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: ServersTab()),
  );
}

void main() {
  testWidgets('shows empty-state copy when host list is empty', (tester) async {
    final repo = _FakeRepository(hosts: const []);
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('No servers yet'), findsOneWidget);
  });

  testWidgets('renders one card per host with the right action label',
      (tester) async {
    final repo = _FakeRepository(hosts: [
      _server(id: 'h1'),
      _server(id: 'h2', canConnect: false),
    ]);
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    expect(find.byKey(const Key('server-h2')), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Not configured'), findsOneWidget);
  });

  testWidgets('shows error and Retry when fetch fails', (tester) async {
    final repo = _FakeRepository(fetchError: Exception('boom'));
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows snackbar when fetchSshConfig fails', (tester) async {
    final repo = _FakeRepository(
      hosts: [_server(id: 'h1')],
      sshError: Exception('nope'),
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.connectCalls, 1);
    expect(find.textContaining('Failed to get SSH config'), findsOneWidget);
  });

  testWidgets('host list provider can refresh on demand', (tester) async {
    final repo = _FakeRepository(hosts: [_server(id: 'h1')]);
    final container = ProviderContainer(
      overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final initial = await container.read(hostListProvider.future);
    expect(initial, hasLength(1));

    repo.hosts = [_server(id: 'h1'), _server(id: 'h2')];
    await container.read(hostListProvider.notifier).refresh();
    final refreshed = await container.read(hostListProvider.future);
    expect(refreshed, hasLength(2));
  });
}
