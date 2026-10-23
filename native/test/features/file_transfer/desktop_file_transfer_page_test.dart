import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/ui/desktop_management.dart';
import 'package:easynode_native/core/ui/desktop_select.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/file_transfer/desktop_file_transfer_page.dart';
import 'package:easynode_native/features/file_transfer/file_transfer_client.dart';
import 'package:easynode_native/features/order/order_layout.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_sftp_panel.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/desktop_server_catalog_provider.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _host = ServerModel.fromJson({
  'id': 'one',
  'name': 'Linux',
  'host': '10.0.0.2',
  'port': 22,
  'connectType': 'ssh',
  'isConfig': true,
});

class _Repository implements ServerRepository {
  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async =>
      SshConnectionConfig.fromJson({'hostId': hostId});
  @override
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager extends SftpSessionManager {
  SftpSessionState? state;
  int refreshes = 0;
  @override
  Iterable<SftpSessionState> get sessions => [?state];
  @override
  SftpSessionState? get activeSession => state;
  @override
  SftpSessionState? sessionFor(String hostId) => state;
  @override
  bool isConnected(String hostId) => state?.isConnected == true;
  @override
  void activate(String hostId) {}
  @override
  Future<SftpSessionState> connect({
    required ServerModel server,
    required SshConnectionConfig config,
    Future<List<SftpFavorite>> Function(String)? loadFavorites,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    state = SftpSessionState(server: server)
      ..update(
        status: SftpConnectionStatus.connected,
        currentPath: '/srv',
        entries: [
          const SftpFileEntry(
            name: 'notes.txt',
            type: '-',
            size: 128,
            modifyTime: null,
            permissions: '-rw-r--r--',
            ownerName: 'root',
            groupName: 'root',
          ),
        ],
      );
    notifyListeners();
    return state!;
  }

  @override
  Future<void> disconnectAll() async {
    state?.dispose();
    state = null;
    notifyListeners();
  }

  @override
  Future<void> refreshActive({bool showLoading = true}) async {
    refreshes++;
  }

  @override
  void dispose() {
    state?.dispose();
    super.dispose();
  }
}

class _Client extends FileTransferClient {
  _Client()
    : super(
        session: const AuthSession(
          serverAddress: 'https://panel.example.com',
          username: 'admin',
          token: 'token',
          deviceId: 'd',
        ),
        cookies: SessionCookieStore.memory(),
        trust: ServerCertificateTrustStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );
  final configs = <Map<String, dynamic>>[];
  @override
  Future<void> connect() async {
    connected = true;
    notifyListeners();
  }

  @override
  void refresh() {}
  @override
  void start(Map<String, dynamic> config) {
    configs.add(config);
  }
}

Widget _app(_Client client, List<_Manager> managers, {bool plus = true}) =>
    ProviderScope(
      overrides: [
        fileTransferClientProvider.overrideWithValue(client),
        isPlusActiveProvider.overrideWithValue(plus),
        desktopServerCatalogProvider.overrideWith(
          (ref) async => HostCatalog(
            hosts: [_host],
            groups: [],
            order: const OrderLayout(
              schemaVersion: 1,
              revision: 0,
              sections: [],
            ),
          ),
        ),
        serverRepositoryProvider.overrideWithValue(_Repository()),
        desktopTerminalPreferencesProvider.overrideWith(
          (ref) => DesktopTerminalPreferences((_) async {}, ''),
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
        home: Scaffold(
          body: DesktopFileTransferPage(
            managerFactory: () {
              final m = _Manager();
              managers.add(m);
              return m;
            },
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'two independent reusable SFTP browsers submit selected source and destination to the server',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client(), managers = <_Manager>[];
      addTearDown(client.dispose);
      await tester.pumpWidget(_app(client, managers));
      await tester.pumpAndSettle();
      for (final side in ['left', 'right']) {
        await tester.tap(find.byKey(ValueKey('transfer-$side-host')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Linux').last);
        await tester.pumpAndSettle();
      }
      expect(find.byType(DesktopSftpPanel), findsNWidgets(2));
      expect(find.text('Connected'), findsNWidgets(2));
      expect(identical(managers[0].state, managers[1].state), isFalse);
      managers[0].state!.selectOnly('notes.txt');
      managers[1].state!.update(currentPath: '/destination');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('transfer-to-right')));
      await tester.pumpAndSettle();
      expect(find.text('/srv/notes.txt'), findsOneWidget);
      expect(find.text('/destination'), findsWidgets);
      await tester.tap(find.text('Start transfer'));
      await tester.pumpAndSettle();
      expect(client.configs.single, {
        'sourceHostId': 'one',
        'targetHostId': 'one',
        'sourcePaths': [
          {'path': '/srv/notes.txt', 'type': '-', 'size': 128},
        ],
        'targetPath': '/destination',
        'method': 'rsync',
        'options': {'delete': false, 'partial': true, 'compress': true},
      });
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Available content width at the desktop's 900px minimum window.
      tester.view.physicalSize = const Size(706, 600);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSftpPanel), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      // Clearing one host disconnects only that browser.
      tester
          .widget<DesktopSelect>(
            find.byKey(const ValueKey('transfer-left-host')),
          )
          .onSelected('');
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSftpPanel), findsOneWidget);
      expect(managers[0].state, isNull);
      expect(managers[1].state!.isConnected, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('minimum window keeps server transfer disabled without Plus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _Client();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client, [], plus: false));
    await tester.pumpAndSettle();
    final button = tester.widget<ManagementButton>(
      find.byKey(const Key('transfer-to-right')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('File transfer requires Plus. Activate it in Settings.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Transfer options'));
    await tester.pumpAndSettle();
    expect(find.text('Resume partial transfers (--partial)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('task filters and expandable details work in a narrow dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _Client();
    addTearDown(client.dispose);
    client.tasks = [
      {
        'taskId': 'done',
        'status': 'completed',
        'sourceHostName': 'Source',
        'targetHostName': 'Destination',
        'sourcePaths': [
          {'path': '/srv/source.txt', 'type': '-', 'size': 128},
        ],
        'targetPath': '/backup',
        'totalSize': 128,
        'options': {'delete': false, 'partial': true, 'compress': true},
        'createTime': 1720000000000,
      },
      {
        'taskId': 'error',
        'status': 'failed',
        'sourceHostName': 'Failed source',
        'targetHostName': 'Target',
        'errorMessage': 'Access denied',
      },
    ];
    await tester.pumpWidget(_app(client, []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();
    expect(find.text('Source → Destination'), findsOneWidget);
    expect(find.text('Failed source → Target'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/srv/source.txt'), findsOneWidget);
    expect(find.text('/backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Failed').first);
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Source → Destination'), findsNothing);
    await tester.tap(find.text('Cancelled').first);
    await tester.pumpAndSettle();
    expect(find.text('No cancelled tasks'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
