import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/features/ai_agent/agent_repository.dart';
import 'package:easynode_native/features/shell/desktop_shell_page.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/servers/server_list_config.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/terminal/terminal_session_resources.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_sftp_panel.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_agent.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_scripts.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_status.dart';
import 'package:easynode_native/features/scripts/script_repository.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:easynode_native/state/desktop_server_list_config_provider.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:easynode_native/state/storage_providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_page.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_pane.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings_dialog.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_workspace.dart';
import 'package:easynode_native/features/terminal/desktop/terminal_catalog_menu.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/desktop_server_catalog_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'desktop_test_support.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';

class _ListSettings extends DesktopServerListConfigNotifier {
  @override
  Future<ServerListConfig> build() async =>
      const ServerListConfig(displayMode: 'list');
}

class _AgentRepository implements AgentRepository {
  @override
  Future<List<AgentSessionSummary>> getTerminalSessions(String hostId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SftpManager extends SftpSessionManager {
  final state = SftpSessionState(server: host('one'))
    ..status = SftpConnectionStatus.connected;
  @override
  SftpSessionState? get activeSession => state;
  @override
  SftpSessionState? sessionFor(String id) => state;
  @override
  bool isConnected(String id) => true;
  @override
  void activate(String id) {}
  @override
  Future<void> openPath(String path, {bool showLoading = true}) async =>
      state.update(currentPath: path);
  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}

class _Resources extends TerminalSessionResources {
  final sftp = _SftpManager();
  @override
  SftpSessionManager sftpForHost(String id) => sftp;
  @override
  void dispose() {
    sftp.dispose();
    super.dispose();
  }
}

class _Settings extends DesktopTerminalSettingsNotifier {
  @override
  Future<DesktopTerminalSettings> build() async =>
      DesktopTerminalSettings.defaults();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DesktopTerminalWorkspace workspace;
  late List<FakeConnection> connections;
  late AppStorage storage;
  late _Resources resources;
  late List<String> windowCalls;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = AppStorage(await SharedPreferences.getInstance());
    resources = _Resources();
    windowCalls = [];
    connections = [];
    workspace = DesktopTerminalWorkspace(
      loadConfig: (id) async => SshConnectionConfig.fromJson({'hostId': id}),
      settings: DesktopTerminalSettings.defaults,
      monitor: FakeMonitor(),
      resources: resources,
      connectionFactory: () {
        final value = FakeConnection();
        connections.add(value);
        return value;
      },
    );
  });
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    bool shell = false,
    double textScale = 1,
    HostCatalog? hostCatalog,
    ScriptCatalog? scriptCatalog,
    String preferences = '',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('easynode/window'), (
          call,
        ) async {
          windowCalls.add(call.method);
          return call.method == 'getFullscreen' ? false : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('easynode/window'),
            null,
          ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              const AuthState(
                session: AuthSession(
                  serverAddress: 'http://localhost',
                  username: 'admin',
                  token: 'token',
                  deviceId: 'device',
                ),
              ),
            ),
          ),
          appStorageProvider.overrideWithValue(storage),
          cookieStoreProvider.overrideWithValue(SessionCookieStore.memory()),
          certificateTrustProvider.overrideWithValue(
            ServerCertificateTrustStore(
              SecureAppStorage(const FlutterSecureStorage()),
            ),
          ),
          agentRepositoryProvider.overrideWithValue(_AgentRepository()),
          isPlusActiveProvider.overrideWithValue(true),
          desktopServerListConfigProvider.overrideWith(_ListSettings.new),
          desktopTerminalScriptCatalogProvider.overrideWith(
            (ref) async => scriptCatalog ?? ScriptCatalog.fromJson({}),
          ),
          desktopTerminalWorkspaceProvider.overrideWith((ref) {
            ref.onDispose(workspace.dispose);
            return workspace;
          }),
          desktopTerminalSettingsProvider.overrideWith(_Settings.new),
          desktopTerminalPreferencesProvider.overrideWith(
            (ref) => DesktopTerminalPreferences((_) async {}, preferences),
          ),
          desktopServerCatalogProvider.overrideWith(
            (ref) async =>
                hostCatalog ??
                HostCatalog.fromJson({
                  'hosts': [
                    {
                      '_id': 'one',
                      'name': 'one',
                      'host': '127.0.0.1',
                      'username': 'root',
                      'isConfig': true,
                    },
                  ],
                  'groups': [],
                }),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: shell
              ? const DesktopShellPage()
              : const Scaffold(body: DesktopTerminalPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'initial terminal page stays disconnected until user opens a session',
    (tester) async {
      await mount(tester);
      expect(find.text('Recent connections'), findsOneWidget);
      expect(workspace.tabs, isEmpty);
      expect(connections, isEmpty);
      expect(find.byType(DesktopTerminalPaneView), findsNothing);
      expect(find.byKey(const Key('terminal-toolbar')), findsNothing);
      workspace.open(host('one'));
      await tester.pump();
      expect(find.byKey(const Key('terminal-toolbar')), findsOneWidget);
      workspace.closeAll();
      await tester.pump();
      expect(find.byKey(const Key('terminal-toolbar')), findsNothing);
      expect(find.text('Recent connections'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('tab, grid and split transitions retain mounted terminals', (
    tester,
  ) async {
    await mount(tester);
    final one = workspace.open(host('one'));
    workspace.open(host('two'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(connections, hasLength(2));
    final firstState = one.activePane.viewKey.currentState;
    expect(firstState, isNotNull);
    expect(find.byType(TerminalView, skipOffstage: false), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
    await tester.pump();
    expect(one.activePane.viewKey.currentState, same(firstState));
    expect(find.byType(TerminalView), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
    await tester.pump();
    workspace.activate(one);
    await tester.pump();
    expect(one.activePane.viewKey.currentState, same(firstState));
    await tester.tap(find.byTooltip('Split left and right'));
    await tester.pump();
    expect(one.panes, hasLength(2));
    await tester.pump();
    expect(connections, hasLength(3));
    expect(one.panes.first.viewKey.currentState, same(firstState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('split search stays usable at the minimum window size', (
    tester,
  ) async {
    await mount(tester, size: const Size(900, 640));
    final tab = workspace.open(host('one'));
    await tester.pump();
    workspace.toggleSplit(tab, horizontal: true);
    await tester.pump();
    connections.first.output('hello world');
    tab.panes.first.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('flat connect menu has no search and opens the selected host', (
    tester,
  ) async {
    await mount(tester);
    workspace.open(host('two'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('terminal-toolbar')),
        matching: find.text('Connect'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(TerminalCatalogMenu<List<ServerModel>>), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('one 127.0.0.1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('terminal-catalog-one')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(workspace.tabs.map((tab) => tab.server.id), ['two', 'one']);
    expect(connections.last.connects, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'group hover reveals ordered hosts and connect all skips unconfigured hosts and RDP',
    (tester) async {
      await mount(
        tester,
        preferences: '{"hostGroupCascader":true}',
        hostCatalog: HostCatalog.fromJson({
          'groups': [
            {'_id': 'cloud', 'name': 'Cloud'},
          ],
          'hosts': [
            {
              '_id': 'one',
              'name': 'One',
              'group': 'cloud',
              'host': 'host-one',
              'isConfig': true,
            },
            {
              '_id': 'two',
              'name': 'Two',
              'group': 'cloud',
              'host': 'host-two',
              'isConfig': true,
            },
            {
              '_id': 'empty',
              'name': 'Unconfigured',
              'group': 'cloud',
              'host': 'host-empty',
            },
            {
              '_id': 'rdp',
              'name': 'RDP',
              'group': 'cloud',
              'host': 'host-rdp',
              'connectType': 'rdp',
              'isConfig': true,
            },
          ],
          'order': {
            'sections': [
              {
                'groupId': 'cloud',
                'itemIds': ['two', 'one', 'empty', 'rdp'],
              },
            ],
          },
        }),
      );
      workspace.open(host('one'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('terminal-toolbar')),
          matching: find.text('Connect'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Two'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('terminal-catalog-group-cloud')),
        ),
      );
      await tester.pump();
      expect(find.text('Connect all'), findsOneWidget);
      expect(find.text('RDP'), findsNothing);
      final root = tester.getRect(
        find.byKey(const Key('terminal-catalog-root')),
      );
      expect(tester.getRect(find.text('Two')).left, greaterThan(root.right));
      expect(
        tester.getRect(find.text('Two')).top,
        lessThan(tester.getRect(find.text('One')).top),
      );
      await tester.tap(find.text('Connect all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(workspace.tabs.map((tab) => tab.server.id), ['one', 'two', 'one']);
      expect(connections, hasLength(3));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('script cascader selects a command without a search field', (
    tester,
  ) async {
    await mount(
      tester,
      preferences: '{"scriptLibraryCascader":true}',
      scriptCatalog: ScriptCatalog.fromJson({
        'groups': [
          {'_id': 'ops', 'name': 'Operations'},
        ],
        'scripts': [
          {
            '_id': 'uptime',
            'name': 'Uptime',
            'group': 'ops',
            'command': 'uptime',
          },
        ],
      }),
    );
    workspace.open(host('one'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('terminal-toolbar')),
        matching: find.text('Scripts'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('terminal-catalog-group-ops')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-catalog-uptime')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(connections.single.writes.join(), contains('uptime'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long connect menu scrolls with the wheel and Escape dismisses it',
    (tester) async {
      workspace.open(host('one'));
      await mount(
        tester,
        hostCatalog: HostCatalog.fromJson({
          'hosts': [
            for (var i = 0; i < 40; i++)
              {
                '_id': 'host-$i',
                'name': 'Host $i',
                'host': 'host-$i',
                'isConfig': true,
              },
          ],
        }),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('terminal-toolbar')),
          matching: find.text('Connect'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final root = find.byKey(const Key('terminal-catalog-root'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: root, matching: find.byType(Scrollable)),
      );
      expect(scroll.position.pixels, 0);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(
        find.descendant(of: root, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(root),
          scrollDelta: const Offset(0, 360),
        ),
      );
      await tester.pump();
      expect(scroll.position.pixels, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(root, findsNothing);
      expect(workspace.tabs.single.server.id, 'one');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings fit minimum window size', (tester) async {
    await mount(tester, size: const Size(900, 640));
    final pageContext = tester.element(find.byType(DesktopTerminalPage));
    showDesktopTerminalSettings(pageContext);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DesktopTerminalSettingsDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'list connect opens SSH and fullscreen retains the workspace and PTY',
    (tester) async {
      await mount(tester, shell: true);
      expect(connections, isEmpty);
      expect(workspace.tabs, isEmpty);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(workspace.tabs, hasLength(1));
      expect(connections.single.connects, 1);
      final pane = workspace.activeTab!.activePane;
      expect(pane.status, DesktopTerminalStatus.connected);
      expect(pane.focusNode.hasFocus, isTrue);
      tester.testTextInput.enterText('whoami');
      expect(connections.single.writes.join(), contains('whoami'));
      final terminalState = pane.viewKey.currentState;
      connections.single.output('list connection output');
      expect(pane.output, contains('list connection output'));
      final before = tester.getSize(find.byType(DesktopTerminalPage));
      await tester.tap(find.byKey(const Key('terminal-fullscreen')));
      await tester.pump();
      expect(find.byKey(const Key('desktop-sidebar')), findsNothing);
      expect(
        tester.getSize(find.byType(DesktopTerminalPage)).width,
        greaterThan(before.width),
      );
      expect(pane.viewKey.currentState, same(terminalState));
      expect(connections.single.closes, 0);
      pane.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('desktop-sidebar')), findsOneWidget);
      expect(pane.viewKey.currentState, same(terminalState));
      await tester.tap(find.byKey(const Key('desktop-menu-servers')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('desktop-menu-terminal')));
      await tester.pump();
      expect(pane.viewKey.currentState, same(terminalState));
      expect(connections.single.connects, 1);
      expect(connections.single.closes, 0);
      expect(windowCalls, isNot(contains('setFullscreen')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(connections.single.closes, 1);
    },
  );

  testWidgets(
    'grid flattens split panes and retains them across maximize and close',
    (tester) async {
      await mount(tester);
      final one = workspace.open(host('one'));
      workspace.toggleSplit(one, horizontal: true);
      workspace.open(host('two'));
      await tester.pump();
      final states = {
        for (final p in workspace.panes) p.id: p.viewKey.currentState,
      };
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      expect(find.byType(DesktopTerminalStatusPanel), findsNothing);
      expect(find.byKey(const Key('terminal-session-tools')), findsNothing);
      expect(find.byType(TerminalView), findsNWidgets(3));
      expect(find.byType(DesktopTerminalStatusBar), findsNWidgets(3));
      final firstTile = find.byKey(
        ValueKey('terminal-tile-${one.panes.first.id}'),
      );
      final secondTile = find.byKey(
        ValueKey('terminal-tile-${one.panes.last.id}'),
      );
      expect(
        tester.getSize(firstTile).height,
        greaterThan(tester.getSize(secondTile).height),
      );
      await tester.tap(
        find.descendant(of: secondTile, matching: find.text('one')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(workspace.activeTab, same(one));
      expect(one.activePane, same(one.panes.last));
      await tester.tapAt(const Offset(640, 10));
      await tester.pump(const Duration(milliseconds: 300));
      final maximize = find.descendant(
        of: secondTile,
        matching: find.byTooltip('Full screen'),
      );
      await tester.tap(maximize);
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      for (final p in workspace.panes) {
        expect(p.viewKey.currentState, same(states[p.id]));
      }
      await tester.tap(
        find.descendant(
          of: secondTile,
          matching: find.byTooltip('Exit fullscreen'),
        ),
      );
      await tester.pump();
      expect(find.byType(TerminalView), findsNWidgets(3));
      final removed = one.panes.last;
      await tester.tap(
        find.descendant(of: secondTile, matching: find.byTooltip('Close')),
      );
      await tester.pump();
      expect(removed.closed, isTrue);
      expect(workspace.panes, hasLength(2));
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      expect(
        workspace.panes.first.viewKey.currentState,
        same(states[workspace.panes.first.id]),
      );
      expect(connections, hasLength(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'SFTP and AI are exclusive, fit the workarea and retain drafts and paths',
    (tester) async {
      await mount(tester);
      final tab = workspace.open(host('one'));
      await tester.pump();
      await tester.tap(find.byTooltip('SFTP'));
      await tester.pump();
      final sftpState = tester.state(find.byType(DesktopSftpPanel));
      expect(find.byType(DesktopSftpPanel), findsOneWidget);
      expect(
        tester.getRect(find.byType(DesktopSftpPanel)).right,
        lessThanOrEqualTo(1280),
      );
      await resources.sftp.openPath('/srv/project');
      final paneView = tester.widget<DesktopTerminalPaneView>(
        find.byType(DesktopTerminalPaneView),
      );
      paneView.onAi('explain this output');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DesktopSftpPanel), findsNothing);
      expect(find.byType(DesktopTerminalAgent), findsOneWidget);
      expect(
        tester.getRect(find.byType(DesktopTerminalAgent)).right,
        lessThanOrEqualTo(1280),
      );
      final agentState = tester.state(find.byType(AgentPanel));
      expect(find.text('explain this output'), findsOneWidget);
      await tester.tap(find.byTooltip('SFTP'));
      await tester.pump();
      expect(find.byType(DesktopTerminalAgent), findsNothing);
      expect(tester.state(find.byType(DesktopSftpPanel)), same(sftpState));
      expect(resources.sftp.state.currentPath, '/srv/project');
      paneView.onAi('next question');
      await tester.pump();
      expect(tester.state(find.byType(AgentPanel)), same(agentState));
      expect(find.text('next question'), findsOneWidget);
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      expect(find.byType(DesktopTerminalAgent), findsOneWidget);
      expect(find.byType(DesktopSftpPanel), findsNothing);
      paneView.onSyncPath('/tmp');
      await tester.pump();
      await tester.pump();
      expect(find.byType(DesktopSftpPanel), findsOneWidget);
      expect(find.byType(DesktopTerminalAgent), findsNothing);
      expect(resources.sftp.state.currentPath, '/tmp');
      expect(tab.activePane.status, DesktopTerminalStatus.connected);
      expect(connections.single.connects, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('desktop AI history retains its terminal scope and draft', (
    tester,
  ) async {
    await mount(tester);
    workspace.open(host('one'));
    await tester.pump();
    tester
        .widget<DesktopTerminalPaneView>(find.byType(DesktopTerminalPaneView))
        .onAi('keep this draft');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final panelState = tester.state(find.byType(AgentPanel));
    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.state(find.byType(AgentPanel)), same(panelState));
    expect(find.text('keep this draft'), findsOneWidget);
    expect(connections.single.connects, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('command editor draft survives hiding and changing layout', (
    tester,
  ) async {
    await mount(tester);
    workspace.open(host('one'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-command-toggle')));
    await tester.pump();
    await tester.pump();
    final field = find.descendant(
      of: find.byType(DesktopTerminalScripts),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'echo draft');
    await tester.tap(find.byKey(const Key('terminal-command-toggle')));
    await tester.pump();
    expect(find.byType(DesktopTerminalScripts), findsNothing);
    await tester.tap(find.byKey(const Key('terminal-command-toggle')));
    await tester.pump();
    expect(find.text('echo draft'), findsOneWidget);
    await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
    await tester.pump();
    expect(find.byType(DesktopTerminalScripts), findsNothing);
    await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
    await tester.pump();
    expect(find.text('echo draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('toolbars align left and narrow workarea scrolls without a bar', (
    tester,
  ) async {
    await mount(
      tester,
      size: const Size(900, 640),
      shell: true,
      textScale: 1.3,
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();
    final toolbar = tester.getRect(find.byKey(const Key('terminal-toolbar')));
    final sessionTools = tester.getRect(
      find.byKey(const Key('terminal-session-tools')),
    );
    final page = tester.getRect(find.byType(DesktopTerminalPage));
    expect(toolbar.left, page.left);
    expect(toolbar.width, page.width);
    expect(sessionTools.left, page.left);
    expect(sessionTools.width, page.width);
    await tester.tap(find.byTooltip('SFTP'));
    await tester.pump();
    final scrollView = find.byKey(const Key('terminal-workarea-scroll'));
    expect(scrollView, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DesktopTerminalPage),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
    final scroll = tester.widget<SingleChildScrollView>(scrollView).controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(
      tester.getRect(find.byType(DesktopSftpPanel)).right,
      lessThanOrEqualTo(page.right),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'grid resizing keeps terminals and per-pane commands target only their own PTY',
    (tester) async {
      await mount(tester);
      final first = workspace.open(host('one'));
      workspace.open(host('two'));
      await tester.pump();
      workspace.syncAll = true;
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      final pane = first.activePane;
      final tile = find.byKey(ValueKey('terminal-tile-${pane.id}'));
      final terminalState = pane.viewKey.currentState;
      final before = tester.getSize(tile).width;
      await tester.drag(
        find.byKey(const Key('terminal-grid-divider-column-0')),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(tester.getSize(tile).width, greaterThan(before));
      expect(pane.viewKey.currentState, same(terminalState));
      final scriptsButton = find.byKey(
        ValueKey('terminal-pane-script-${pane.id}'),
      );
      await tester.tap(scriptsButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final editor = find.descendant(
        of: find.byType(DesktopTerminalScripts),
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, 'echo own-pane');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(scriptsButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('echo own-pane'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(connections.first.writes.join(), contains('echo own-pane'));
      expect(connections.last.writes, isEmpty);
      expect(pane.viewKey.currentState, same(terminalState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final count in [5, 7]) {
    testWidgets(
      '$count grid terminals fill the last row and retain sessions when changing layout',
      (tester) async {
        await mount(tester, size: Size(1280, count == 5 ? 800 : 1100));
        for (var i = 0; i < count; i++) {
          workspace.open(host('host-$i'));
        }
        await tester.pump();
        final states = {
          for (final pane in workspace.panes)
            pane.id: pane.viewKey.currentState,
        };
        await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
        await tester.pump();
        List<Rect> tiles() => [
          for (final pane in workspace.panes)
            tester.getRect(find.byKey(ValueKey('terminal-tile-${pane.id}'))),
        ];
        void expectRowsFillWidth() {
          final rects = tiles();
          final rows = count == 5 ? [3, 2] : [3, 3, 1];
          var index = 0;
          var top = rects.first.top;
          final height = rects.first.height;
          for (final columns in rows) {
            var left = rects.first.left;
            for (var col = 0; col < columns; col++) {
              final rect = rects[index++];
              expect(rect.left, closeTo(left, .01));
              expect(rect.top, closeTo(top, .01));
              expect(rect.width, closeTo(1280 / columns, .01));
              expect(rect.height, closeTo(height, .01));
              left = rect.right;
            }
            expect(left, closeTo(1280, .01));
            top += height;
          }
        }

        expectRowsFillWidth();
        expect(
          find.byKey(const Key('terminal-grid-divider-column-0')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('terminal-grid-divider-row-0')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('terminal-horizontal-toggle')));
        await tester.pump();
        expect(tiles().every((rect) => rect.width == 500), isTrue);
        await tester.tap(find.byKey(const Key('terminal-fit-grid')));
        await tester.pump();
        expectRowsFillWidth();
        for (final pane in workspace.panes) {
          expect(pane.viewKey.currentState, same(states[pane.id]));
        }
        expect(connections, hasLength(count));
        expect(
          connections.every((connection) => connection.connects == 1),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'six terminals retain PTYs through horizontal layout and maximize',
    (tester) async {
      await mount(tester);
      for (var i = 0; i < 6; i++) {
        workspace.open(host('host-$i'));
      }
      await tester.pump();
      final states = {
        for (final p in workspace.panes) p.id: p.viewKey.currentState,
      };
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terminal-horizontal-toggle')));
      await tester.pump();
      final firstTile = find.byKey(
        ValueKey('terminal-tile-${workspace.panes.first.id}'),
      );
      expect(tester.getSize(firstTile).width, 500);
      await tester.tap(
        find.descendant(of: firstTile, matching: find.byTooltip('Full screen')),
      );
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(tester.getSize(firstTile).width, 1280);
      await tester.tap(
        find.descendant(
          of: firstTile,
          matching: find.byTooltip('Exit fullscreen'),
        ),
      );
      await tester.pump();
      expect(tester.getSize(firstTile).width, 500);
      await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
      await tester.pump();
      for (final p in workspace.panes) {
        expect(p.viewKey.currentState, same(states[p.id]));
      }
      expect(connections, hasLength(6));
      expect(
        connections.every((c) => c.connects == 1 && c.closes == 0),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('AI and three grid terminals fit the minimum desktop window', (
    tester,
  ) async {
    await mount(tester, shell: true, size: const Size(900, 640));
    await tester.tap(find.text('Connect'));
    await tester.pump();
    workspace.open(host('two'));
    workspace.open(host('three'));
    await tester.pump();
    tester
        .widget<DesktopTerminalPaneView>(find.byType(DesktopTerminalPaneView))
        .onAi('check host');
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-layout-toggle')));
    await tester.pump();
    expect(find.byType(TerminalView), findsNWidgets(3));
    expect(find.byType(DesktopTerminalAgent), findsOneWidget);
    final page = tester.getRect(find.byType(DesktopTerminalPage));
    expect(find.text('Your global operations assistant'), findsNothing);
    expect(
      find.textContaining('This assistant is bound to the current terminal'),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(DesktopTerminalAgent)).right,
      lessThanOrEqualTo(page.right),
    );
    for (final pane in workspace.panes) {
      expect(
        tester.getSize(find.byKey(ValueKey('terminal-tile-${pane.id}'))).width,
        greaterThanOrEqualTo(220),
      );
    }
    expect(connections, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'terminal context menu follows selection and syncs the actual PTY directory',
    (tester) async {
      await mount(tester);
      final tab = workspace.open(host('one'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      Future<void> menu() async {
        await tester.tapAt(
          tester.getCenter(find.byType(TerminalView)),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      }

      await menu();
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Find'), findsOneWidget);
      expect(find.text('Send to AI assistant'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Open path in SFTP'), findsNothing);
      expect(find.text('Export terminal output'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byTooltip('SFTP'));
      await tester.pump();
      await menu();
      expect(find.text('Open path in SFTP'), findsOneWidget);
      await tester.tap(find.text('Open path in SFTP'));
      await tester.pump();
      final marker = RegExp(
        r'__ENAI_[a-f0-9]+__',
      ).firstMatch(connections.single.writes.last)!.group(0)!;
      connections.single.output(
        '$marker:begin\r\n/srv/current\r\n$marker:end:0\r\n',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(resources.sftp.state.currentPath, '/srv/current');
      final pane = tab.activePane;
      pane.terminal.write('\x1b[H\x1b[2J\x1b[3Jabcdefabcdef');
      pane.viewController.setSelection(
        pane.terminal.buffer.createAnchor(0, 0),
        pane.terminal.buffer.createAnchor(12, 0),
      );
      await menu();
      expect(find.text('Send to AI assistant'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Open container shell'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.text('Docker container actions')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.text('Open container shell'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((e) => e.data)
            .join(' | '),
      );
      await tester.tap(find.text('Open container shell'));
      await tester.pump();
      expect(
        connections.single.writes.last,
        'docker exec -it abcdefabcdef sh\n',
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
