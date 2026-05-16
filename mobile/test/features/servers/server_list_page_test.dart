import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/auth_session.dart';
import 'package:mobile/features/servers/server_list_page.dart';
import 'package:mobile/features/servers/server_model.dart';
import 'package:mobile/features/servers/server_repository.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';

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

const _session = AuthSession(
  serverAddress: 'https://example.com',
  username: 'root',
  token: 't',
  deviceId: 'd',
);

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

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows empty state when host list is empty', (tester) async {
    final repo = _FakeRepository(hosts: const []);
    await tester.pumpWidget(_wrap(ServerListPage(
      repository: repo,
      session: _session,
      onLogout: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无服务器'), findsOneWidget);
  });

  testWidgets('renders one tile per host with connect button', (tester) async {
    final repo = _FakeRepository(hosts: [
      _server(id: 'h1'),
      _server(id: 'h2', canConnect: false),
    ]);
    await tester.pumpWidget(_wrap(ServerListPage(
      repository: repo,
      session: _session,
      onLogout: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    expect(find.byKey(const Key('server-h2')), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);
  });

  testWidgets('shows error and retry button when fetch fails', (tester) async {
    final repo = _FakeRepository(fetchError: Exception('boom'));
    await tester.pumpWidget(_wrap(ServerListPage(
      repository: repo,
      session: _session,
      onLogout: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('shows snackbar when fetchSshConfig fails', (tester) async {
    final repo = _FakeRepository(
      hosts: [_server(id: 'h1')],
      sshError: Exception('nope'),
    );
    await tester.pumpWidget(_wrap(ServerListPage(
      repository: repo,
      session: _session,
      onLogout: () {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.connectCalls, 1);
    expect(find.textContaining('获取 SSH 参数失败'), findsOneWidget);
  });

  testWidgets('logout button calls onLogout', (tester) async {
    var loggedOut = 0;
    final repo = _FakeRepository(hosts: const []);
    await tester.pumpWidget(_wrap(ServerListPage(
      repository: repo,
      session: _session,
      onLogout: () => loggedOut++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('退出登录'));
    await tester.pump();
    expect(loggedOut, 1);
  });
}
