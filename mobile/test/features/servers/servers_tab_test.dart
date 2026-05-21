import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_model.dart';
import 'package:mobile/features/servers/server_group_model.dart';
import 'package:mobile/features/servers/server_repository.dart';
import 'package:mobile/features/servers/servers_tab.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/state/auth_notifier.dart';
import 'package:mobile/state/auth_state.dart';
import 'package:mobile/state/api_providers.dart';
import 'package:mobile/state/host_list_notifier.dart';
import 'package:mobile/state/group_list_notifier.dart';

class _FakeRepository implements ServerRepository {
  _FakeRepository({
    this.hosts = const [],
    this.groups = const [],
    this.fetchError,
    this.groupFetchError,
    SshConnectionConfig? config,
    this.sshError,
  }) : config = config ?? _defaultConfig;

  List<ServerModel> hosts;
  List<ServerGroupModel> groups;
  Object? fetchError;
  Object? groupFetchError;
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
  Future<List<ServerGroupModel>> fetchGroups() async {
    if (groupFetchError != null) throw groupFetchError!;
    return groups;
  }

  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    connectCalls++;
    if (sshError != null) throw sshError!;
    return config;
  }
}

class _RecordingAuthNotifier extends AuthNotifier {
  _RecordingAuthNotifier(super.ref) : super(AuthState.empty);

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

ServerModel _server({
  String id = 'h1',
  bool canConnect = true,
  String group = '',
}) {
  return ServerModel.fromJson({
    'id': id,
    'name': 'srv-$id',
    'host': '10.0.0.2',
    'port': 22,
    'username': 'root',
    'authType': 'password',
    'group': group,
    'tag': const [],
    'expired': !canConnect,
    'isConfig': canConnect,
  });
}

ServerGroupModel _group({
  String id = 'default',
  String name = 'Default group',
  int index = 1,
}) {
  return ServerGroupModel.fromJson({
    'id': id,
    'name': name,
    'index': index,
  });
}

Widget _wrap({required ServerRepository repo}) {
  return ProviderScope(
    overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      // Force English so test assertions stay stable regardless of host locale.
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ServersTab(),
    ),
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

  testWidgets('hides group filter when only the default group exists',
      (tester) async {
    final repo = _FakeRepository(
      hosts: [_server(id: 'h1', group: 'default')],
      groups: [_group()],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('All'), findsNothing);
    expect(find.textContaining('Default group'), findsNothing);
    expect(find.byKey(const Key('server-h1')), findsOneWidget);
  });

  testWidgets('shows group filters and filters cards by selected group',
      (tester) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1', group: 'default'),
        _server(id: 'h2', group: 'overseas'),
      ],
      groups: [
        _group(),
        _group(id: 'overseas', name: 'Overseas', index: 2),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('All 2'), findsOneWidget);
    expect(find.text('Default group 1'), findsOneWidget);
    expect(find.text('Overseas 1'), findsOneWidget);

    await tester.tap(find.text('Overseas 1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsNothing);
    expect(find.byKey(const Key('server-h2')), findsOneWidget);
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

  testWidgets('group list provider can refresh on demand', (tester) async {
    final repo = _FakeRepository(groups: [_group()]);
    final container = ProviderContainer(
      overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final initial = await container.read(groupListProvider.future);
    expect(initial, hasLength(1));

    repo.groups = [_group(), _group(id: 'g2', name: 'Overseas', index: 2)];
    await container.read(groupListProvider.notifier).refresh();
    final refreshed = await container.read(groupListProvider.future);
    expect(refreshed, hasLength(2));
  });

  testWidgets('signs out when initial host fetch is unauthorized',
      (tester) async {
    final repo = _FakeRepository(
      fetchError: UnauthorizedFailure('expired', statusCode: 401),
    );
    late _RecordingAuthNotifier auth;
    final container = ProviderContainer(
      overrides: [
        serverRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith((ref) {
          auth = _RecordingAuthNotifier(ref);
          return auth;
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(hostListProvider.future),
      throwsA(isA<UnauthorizedFailure>()),
    );
    expect(auth.signOutCalls, 1);
  });
}
