import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/order/order_layout.dart';
import 'package:easynode_native/features/servers/server_form_data.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_group_model.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/servers/servers_tab.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/host_list_notifier.dart';
import 'package:easynode_native/state/group_list_notifier.dart';

class _FakeRepository extends ServerRepository {
  _FakeRepository({
    this.hosts = const [],
    this.groups = const [],
    this.fetchError,
    // ignore: unused_element_parameter
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
  List<OrderChange> submittedOrderChanges = const [];

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
    proxyType: '',
    proxy: null,
    jumpHosts: [],
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
  Future<HostCatalog> fetchCatalog() async {
    if (fetchError != null) throw fetchError!;
    if (groupFetchError != null) throw groupFetchError!;
    return HostCatalog(
      hosts: hosts,
      groups: groups,
      order: OrderLayout(
        schemaVersion: 1,
        revision: 4,
        sections: groups
            .map(
              (group) => OrderSection(
                groupId: group.id,
                itemIds: hosts
                    .where((host) => host.group == group.id)
                    .map((host) => host.id)
                    .toList(),
              ),
            )
            .toList(),
        flatItemIds: hosts.map((host) => host.id).toList(),
      ),
    );
  }

  @override
  Future<OrderLayout> updateOrder(
    int revision,
    List<OrderChange> changes,
  ) async {
    submittedOrderChanges = changes;
    return (await fetchCatalog()).order;
  }

  @override
  Future<String> createHost(ServerFormData form) async {
    hosts = [...hosts, _server(id: 'created', group: form.group)];
    return 'success';
  }

  @override
  Future<String> updateHost(ServerFormData form) async {
    return 'success';
  }

  @override
  Future<String> deleteHost(String hostId) async {
    hosts = hosts.where((host) => host.id != hostId).toList(growable: false);
    return 'success';
  }

  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    connectCalls++;
    if (sshError != null) throw sshError!;
    return config;
  }

  @override
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId) async =>
      const [];
}

class _RecordingAuthNotifier extends AuthNotifier {
  _RecordingAuthNotifier(Ref ref) : super(ref, AuthState.empty);

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
}) {
  return ServerGroupModel.fromJson({'id': id, 'name': name});
}

Widget _wrap({required ServerRepository repo}) {
  return ProviderScope(
    overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
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

Future<void> _revealServerActions(WidgetTester tester, String serverId) async {
  await tester.drag(
    find.byKey(ValueKey('server-swipe-$serverId')),
    const Offset(-230, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows empty-state copy when host list is empty', (tester) async {
    final repo = _FakeRepository(hosts: const []);
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('No servers yet'), findsOneWidget);
  });

  testWidgets('renders compact cards without persistent action icons', (
    tester,
  ) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1'),
        _server(id: 'h2', canConnect: false),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    expect(find.byKey(const Key('server-h2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('server-action-edit-h1')).hitTestable(),
      findsNothing,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.terminal_rounded), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('server-h1'))).height,
      lessThan(80),
    );
  });

  testWidgets('reveals actions, expands details, and copies the host address', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map<Object?, Object?>)['text']
              ?.toString();
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = _FakeRepository(
      hosts: [_server(id: 'h1', group: 'default')],
      groups: [_group()],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copy host address').hitTestable(), findsNothing);

    await _revealServerActions(tester, 'h1');
    expect(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-action-edit-h1')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-action-delete-h1')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copy host address').hitTestable(), findsOneWidget);
    expect(find.text('Default group'), findsOneWidget);
    expect(find.text('Expiry date'), findsOneWidget);
    expect(find.text('Console URL'), findsOneWidget);
    expect(find.text('Login command'), findsOneWidget);
    expect(find.text('-'), findsNWidgets(5));
    final details = find.byKey(const ValueKey('server-details-h1'));
    expect(
      find.descendant(of: details, matching: find.text('Edit')),
      findsNothing,
    );
    expect(
      find.descendant(of: details, matching: find.text('Delete')),
      findsNothing,
    );
    await tester.tap(find.byIcon(Icons.copy_outlined).hitTestable());
    await tester.pump();

    expect(copiedText, '10.0.0.2');
    expect(find.text('Host address copied'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-h1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-details-h1')), findsNothing);
    expect(repo.connectCalls, 0);

    repo.sshError = Exception('stop test connection');
    await tester.tap(find.byKey(const Key('server-h1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.connectCalls, 1);
  });

  testWidgets('keeps only one server action pane open', (tester) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1'),
        _server(id: 'h2'),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    await _revealServerActions(tester, 'h1');
    expect(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('server-h2')));
    await tester.pumpAndSettle();
    expect(repo.connectCalls, 0);
    expect(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
      findsNothing,
    );

    await _revealServerActions(tester, 'h1');
    await _revealServerActions(tester, 'h2');
    expect(
      find.byKey(const ValueKey('server-action-details-h1')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('server-action-details-h2')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('opens delete confirmation from the swipe action', (
    tester,
  ) async {
    final repo = _FakeRepository(hosts: [_server(id: 'h1')]);
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    await _revealServerActions(tester, 'h1');
    await tester.tap(
      find.byKey(const ValueKey('server-action-delete-h1')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete server?'), findsOneWidget);
    expect(
      find.text('Delete "srv-h1"? This cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('shows and collapses the default group section', (tester) async {
    final repo = _FakeRepository(
      hosts: [_server(id: 'h1', group: 'default')],
      groups: [_group()],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('Default group'), findsOneWidget);
    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    final groupHeader = find.byKey(const ValueKey('server-group-default'));
    final headerMaterial = tester.widget<Material>(groupHeader);
    final groupName = tester.widget<Text>(
      find.descendant(of: groupHeader, matching: find.text('Default group')),
    );
    final count = find.descendant(of: groupHeader, matching: find.text('1'));
    final expandIcon = find.descendant(
      of: groupHeader,
      matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
    );
    expect(headerMaterial.color, Colors.transparent);
    expect(tester.getSize(groupHeader).height, 38);
    expect(groupName.style?.fontSize, 13);
    expect(groupName.style?.color, AppColorTheme.defaultLight.muted);
    expect(
      find.descendant(of: groupHeader, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      tester.getCenter(count).dx,
      lessThan(tester.getCenter(expandIcon).dx),
    );

    await tester.tap(find.byKey(const ValueKey('server-group-toggle-default')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsNothing);
  });

  testWidgets('enters grouped order mode and renders drag handles', (
    tester,
  ) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1'),
        _server(id: 'h2'),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    final normalCardHeight = tester
        .getSize(find.byKey(const Key('server-h1')))
        .height;
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust order'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    expect(find.byKey(const ValueKey('server-swipe-h1')), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    final orderCardHeight = tester
        .getSize(find.byKey(const Key('server-h1')))
        .height;
    expect(orderCardHeight, normalCardHeight);
    expect(orderCardHeight, lessThan(80));

    final drag = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_handle).first),
    );
    await drag.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('app-order-drag-proxy')), findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.submittedOrderChanges.single.scope, 'groupItems');
    expect(repo.submittedOrderChanges.single.groupId, 'default');
    expect(repo.submittedOrderChanges.single.orderedIds, ['h1', 'h2']);
  });

  testWidgets('submits one order change for each server group', (tester) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1', group: 'default'),
        _server(id: 'h2', group: 'overseas'),
      ],
      groups: [
        _group(),
        _group(id: 'overseas', name: 'Overseas'),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust order'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.submittedOrderChanges, hasLength(2));
    expect(
      repo.submittedOrderChanges.map((change) => change.scope),
      everyElement('groupItems'),
    );
    expect(
      {
        for (final change in repo.submittedOrderChanges)
          change.groupId: change.orderedIds,
      },
      {
        'default': ['h1'],
        'overseas': ['h2'],
      },
    );
  });

  testWidgets('groups search and adjust order under the more actions menu', (
    tester,
  ) async {
    final repo = _FakeRepository(hosts: [_server(id: 'h1')]);
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Search'), findsNothing);
    expect(find.byTooltip('Adjust order'), findsNothing);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byTooltip('Add server'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    final menu = tester.widget<PopupMenuButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('server-more-menu')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    expect(menu.offset, const Offset(0, -16));
    expect(
      menu.popUpAnimationStyle?.duration,
      const Duration(milliseconds: 120),
    );
    expect(
      menu.popUpAnimationStyle?.reverseDuration,
      const Duration(milliseconds: 90),
    );

    final moreX = tester.getCenter(find.byTooltip('More actions')).dx;
    final addX = tester.getCenter(find.byTooltip('Add server')).dx;
    expect(addX, lessThan(moreX));

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Adjust order'), findsOneWidget);
    final searchMenuItem = find.ancestor(
      of: find.text('Search'),
      matching: find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String>,
      ),
    );
    final menuRect = tester.getRect(searchMenuItem);
    final moreCenter = tester.getCenter(find.byTooltip('More actions'));
    expect(menuRect.left, lessThan(moreCenter.dx));
    expect(menuRect.right, greaterThan(moreCenter.dx));
    expect(menuRect.top, greaterThan(tester.getRect(find.text('Servers')).top));

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
  });

  testWidgets('shows all group sections and collapses them independently', (
    tester,
  ) async {
    final repo = _FakeRepository(
      hosts: [
        _server(id: 'h1', group: 'default'),
        _server(id: 'h2', group: 'overseas'),
      ],
      groups: [
        _group(),
        _group(id: 'overseas', name: 'Overseas'),
      ],
    );
    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('Default group'), findsOneWidget);
    expect(find.text('Overseas'), findsOneWidget);
    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    expect(find.byKey(const Key('server-h2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-group-divider-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('server-group-toggle-overseas')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-h1')), findsOneWidget);
    expect(find.byKey(const Key('server-h2')), findsNothing);
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

    await tester.tap(find.byKey(const Key('server-h1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.connectCalls, 1);
    expect(find.byKey(const ValueKey('server-details-h1')), findsNothing);
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

    repo.groups = [_group(), _group(id: 'g2', name: 'Overseas')];
    await container.read(groupListProvider.notifier).refresh();
    final refreshed = await container.read(groupListProvider.future);
    expect(refreshed, hasLength(2));
  });

  testWidgets('host notifier does not own unauthorized session side effects', (
    tester,
  ) async {
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
    container.read(authProvider);
    addTearDown(container.dispose);

    await expectLater(
      container.read(hostListProvider.future),
      throwsA(isA<UnauthorizedFailure>()),
    );
    expect(auth.signOutCalls, 0);
  });
}
