import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/ui/desktop_management.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_repository.dart';
import 'package:easynode_native/features/batch/desktop_batch_page.dart';
import 'package:easynode_native/features/batch/batch_execution.dart';
import 'package:easynode_native/features/batch/batch_repository.dart';
import 'package:easynode_native/features/order/order_layout.dart';
import 'package:easynode_native/features/scheduled_tasks/desktop_scheduled_tasks_page.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_repository.dart';
import 'package:easynode_native/features/scripts/desktop_scripts_page.dart';
import 'package:easynode_native/features/scripts/script_repository.dart';
import 'package:easynode_native/features/settings/desktop_credentials_page.dart';
import 'package:easynode_native/features/settings/desktop_settings_page.dart';
import 'package:easynode_native/features/settings/desktop_settings_repository.dart';
import 'package:easynode_native/features/settings/desktop_notification_settings.dart';
import 'package:easynode_native/features/settings/desktop_ai_settings.dart';
import 'package:easynode_native/features/settings/desktop_plus_settings.dart';
import 'package:easynode_native/features/settings/desktop_settings_widgets.dart';
import 'package:easynode_native/features/settings/desktop_mcp_settings.dart';
import 'package:easynode_native/features/settings/settings_repository.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:easynode_native/state/desktop_server_catalog_provider.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easynode_native/core/ui/desktop_select.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:socket_io_client/src/manager.dart';

class _Api extends ApiClient {
  _Api({this.plusActive = false})
    : super(
        serverAddress: 'https://panel.example.com',
        cookieStore: SessionCookieStore.memory(),
      );
  final bool plusActive;
  final reads = <String>[];
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    reads.add(path);
    return {
      'data': switch (path) {
        '/get-ssh-list' => [
          {
            'id': 'default',
            'name': 'Default credential',
            'authType': 'password',
          },
          {'id': 'key1', 'name': 'Production', 'authType': 'password'},
        ],
        '/plus-info' =>
          plusActive ? {'active': true, 'key': 'active-plus-license-key'} : {},
        '/plus-discount' => {},
        '/mfa2-status' => false,
        '/log' => {'list': []},
        '/ip-access-rules' => {'ipWhiteList': [], 'currentIp': '127.0.0.1'},
        '/proxy' => [],
        '/notify' => [
          {'type': 'login', 'desc': '登录提醒', 'sw': true},
        ],
        '/notify-config' => {
          'type': 'tg',
          'tg': {'token': 'bot-token', 'chatId': '-100'},
        },
        '/agent/mcp-servers' => [],
        _ => throw StateError('Unexpected GET $path'),
      },
    };
  }
}

class _Settings extends SettingsRepository {
  _Settings(_Api api) : super(apiClient: api);
  final credentials = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<void> updateCredential({
    required String id,
    required String name,
    required String authType,
    String password = '',
    String privateKey = '',
    String openSSHKeyPassword = '',
  }) async {
    credentials.add({
      'id': id,
      'name': name,
      'authType': authType,
      'password': password,
      'privateKey': privateKey,
    });
    if (fail) throw ApiFailure('Save unavailable');
  }
}

class _Scripts extends ScriptRepository {
  bool fail = false;
  final created = <ScriptFormData>[];
  @override
  Future<ScriptCatalog> fetchCatalog() async => ScriptCatalog.fromJson({
    'groups': [
      {'id': 'default', 'name': 'Default'},
      {'id': 'builtin', 'name': 'Builtin'},
    ],
    'scripts': [
      {
        'id': 'script1',
        'name': 'Uptime',
        'command': 'uptime',
        'group': 'default',
      },
      {
        'id': 'builtin1',
        'name': 'Built in',
        'command': 'date',
        'group': 'builtin',
      },
    ],
  });
  @override
  Future<String> createScript(ScriptFormData form) async {
    created.add(form);
    if (fail) throw ApiFailure('Save unavailable');
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scheduled extends ScheduledTaskRepository {
  final writes = <ScheduledTaskFormData>[];
  bool fail = false;
  final keywords = <String>[];
  final runQueries = <Map<String, Object?>>[];
  final task = ScheduledTask.fromJson({
    'id': 'task1',
    'name': 'Backup',
    'enabled': true,
    'hostIds': ['host1'],
    'cron': '0 2 * * *',
    'timezone': 'UTC',
    'timeoutSeconds': 120,
    'script': {'type': 'inline', 'command': 'backup', 'useBase64': true},
  });
  @override
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''}) async {
    keywords.add(keyword);
    return [task];
  }

  @override
  Future<ScheduledTask> fetchTask(String id) async => task;
  @override
  Future<ScheduledTask> createTask(ScheduledTaskFormData form) async {
    writes.add(form);
    if (fail) throw ApiFailure('Save unavailable');
    return task;
  }

  @override
  Future<ScheduledTask> updateTask(ScheduledTaskFormData form) async {
    writes.add(form);
    return task;
  }

  @override
  Future<ScheduledTaskRunPage> fetchRuns({
    String? taskId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    runQueries.add({
      'taskId': taskId,
      'status': status,
      'page': page,
      'pageSize': pageSize,
    });
    return ScheduledTaskRunPage.fromJson({
      'items': [],
      'total': 120,
      'page': page,
      'pageSize': pageSize,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Agent extends AgentRepository {
  _Agent(super.api);
  AgentProviderConfig? saved;
  bool fail = false;
  @override
  Future<AgentProviderConfig> getConfig() async =>
      AgentProviderConfig.fromJson({
        'apiUrl': 'https://api.example.com/v1',
        'apiKey': 'secret',
        'models': ['model-a'],
        'contextLimit': 65536,
        'maxSteps': 25,
        'legacyField': 'retain',
        'ui': {'petEnabled': false},
      });
  @override
  Future<void> saveProvider(AgentProviderConfig config) async {
    saved = config;
    if (fail) throw ApiFailure('Save unavailable');
  }
}

class _DesktopSettings extends DesktopSettingsRepository {
  _DesktopSettings(super.api);
  Map<String, dynamic>? saved;
  bool fail = false;
  int deviceReads = 0;
  final released = <String>[];
  final devices = <Map<String, dynamic>>[
    {
      'instanceId': 'abcd-current',
      'ip': '127.0.0.1',
      'version': '3.0.0',
      'isCurrent': true,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    },
    {
      'instanceId': 'efgh-other',
      'ip': '127.0.0.2',
      'version': '3.0.1',
      'isCurrent': false,
      'lastSeen': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    },
  ];
  @override
  Future<Map<String, dynamic>> plusDevices() async {
    deviceReads++;
    return {'devices': devices, 'deviceLimit': 3};
  }

  @override
  Future<void> releasePlusDevice(String instanceId) async {
    released.add(instanceId);
    devices.removeWhere((device) => device['instanceId'] == instanceId);
  }

  @override
  Future<void> saveNotifications(Map<String, dynamic> config) async {
    saved = config;
    if (fail) throw ApiFailure('Test notification failed');
  }
}

class _Batch extends BatchRepository {
  _Batch(super.api);
  List<Map<String, dynamic>> records = [];
  final pages = <int>[];
  @override
  Future<BatchRecordPage> fetch({int page = 1, int pageSize = 20}) async {
    pages.add(page);
    return BatchRecordPage.fromJson({
      'items': records.skip((page - 1) * pageSize).take(pageSize).toList(),
      'total': records.length,
      'page': page,
    });
  }

  @override
  Future<BatchOutput> output(String id, {int offset = 0}) async =>
      BatchOutput.fromJson({
        'result': 'saved output',
        'nextOffset': 12,
        'hasMore': false,
      });
}

class _BatchSocket extends sio.Socket {
  _BatchSocket()
    : super(
        Manager(uri: 'http://localhost:8082', options: {'autoConnect': false}),
        '/',
        {},
      );
  final commands = <dynamic>[];
  @override
  sio.Socket connect() {
    connected = true;
    emitReserved('connect');
    return this;
  }

  @override
  void emit(String event, [dynamic data]) {
    if (event == 'ws_onekey') commands.add(data);
  }

  @override
  void dispose() {
    connected = false;
    clearListeners();
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  ProviderContainer container, {
  Locale locale = const Locale('zh'),
  bool dark = false,
  double scale = 1,
  double width = 900,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [
            dark ? AppColorTheme.defaultDark : AppColorTheme.defaultLight,
          ],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(
              left: 194,
              right: 10,
              top: 10,
              bottom: 10,
            ),
            child: page,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(
  _Api api, {
  _Settings? settings,
  _Scripts? scripts,
  _Scheduled? scheduled,
  _Agent? agent,
  _DesktopSettings? desktopSettings,
  _Batch? batch,
  BatchExecution? batchExecution,
}) => ProviderContainer(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    authProvider.overrideWith((ref) => AuthNotifier(ref, const AuthState())),
    settingsRepositoryProvider.overrideWithValue(settings ?? _Settings(api)),
    scriptRepositoryProvider.overrideWithValue(scripts ?? _Scripts()),
    scheduledTaskRepositoryProvider.overrideWithValue(
      scheduled ?? _Scheduled(),
    ),
    agentRepositoryProvider.overrideWithValue(agent ?? _Agent(api)),
    desktopSettingsRepositoryProvider.overrideWithValue(
      desktopSettings ?? _DesktopSettings(api),
    ),
    batchRepositoryProvider.overrideWithValue(batch ?? _Batch(api)),
    batchExecutionProvider.overrideWith((ref) {
      final execution =
          batchExecution ??
          BatchExecution(
            session: const AuthSession(
              serverAddress: 'https://panel.example.com',
              username: 'admin',
              token: 'token',
              deviceId: 'device',
            ),
            cookies: SessionCookieStore.memory(),
            trust: ServerCertificateTrustStore(
              SecureAppStorage(const FlutterSecureStorage()),
            ),
          );
      ref.onDispose(execution.dispose);
      return execution;
    }),
    desktopServerCatalogProvider.overrideWith(
      (ref) async => HostCatalog(
        hosts: [
          ServerModel.fromJson({
            'id': 'host1',
            'name': 'Production',
            'host': '127.0.0.1',
            'port': 22,
            'connectType': 'ssh',
            'isConfig': true,
          }),
        ],
        groups: [],
        order: const OrderLayout(schemaVersion: 1, revision: 0, sections: []),
      ),
    ),
  ],
);

void main() {
  testWidgets(
    'batch submission shows live rows and refreshes newest history after completion',
    (tester) async {
      final api = _Api();
      final batch = _Batch(api)
        ..records = [
          for (var i = 0; i < 40; i++)
            {
              'id': 'old-$i',
              'name': 'Old $i',
              'status': '执行成功',
              'command': 'date',
            },
        ];
      final cookie = SessionCookieStore.memory();
      await cookie.saveFromSetCookieHeaders(['session=abc']);
      final socket = _BatchSocket();
      final execution = BatchExecution(
        session: const AuthSession(
          serverAddress: 'http://localhost:18090',
          username: 'admin',
          token: 'token',
          deviceId: 'device',
        ),
        cookies: cookie,
        trust: ServerCertificateTrustStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        socketFactory: (address, _) {
          expect(address, 'http://localhost:8082');
          return socket;
        },
      );
      final container = _container(
        api,
        batch: batch,
        batchExecution: execution,
      );
      addTearDown(container.dispose);
      await _pump(tester, const DesktopBatchPage(), container);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(batch.pages.last, 2);
      await tester.tap(find.widgetWithText(ManagementButton, '执行指令'));
      await tester.pumpAndSettle();
      expect(find.text('全选 / 取消全选'), findsNothing);
      await tester.tap(find.byKey(const Key('batch-hosts')));
      await tester.pumpAndSettle();
      expect(find.text('仅显示已配置 SSH 连接的实例'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Production'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('batch-command')), 'uptime');
      await tester.tap(find.widgetWithText(ManagementButton, '开始执行'));
      await tester.pumpAndSettle();
      expect(socket.commands.single['hostIds'], ['host1']);
      final record = <String, dynamic>{
        'id': 'new',
        'batchId': 'new-batch',
        'hostId': 'host1',
        'name': 'Live production',
        'host': '127.0.0.1',
        'port': 22,
        'command': 'uptime',
        'status': '执行中',
        'result': 'up 10 days',
      };
      socket.emitReserved('output', [record]);
      await tester.pumpAndSettle();
      expect(find.text('Live production'), findsOneWidget);
      expect(find.text('up 10 days'), findsOneWidget);
      expect(find.text('当前批次 1 条'), findsOneWidget);
      batch.records.insert(0, {...record, 'status': '执行成功'});
      socket.emitReserved('exec_complete');
      await tester.pumpAndSettle();
      expect(batch.pages.last, 1);
      expect(execution.active, false);
      expect(find.text('Live production'), findsOneWidget);
      expect(find.text('当前批次 1 条'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'credential edit keeps saved secret blank and preserves input after failure',
    (tester) async {
      final api = _Api();
      final settings = _Settings(api)..fail = true;
      final container = _container(api, settings: settings);
      addTearDown(container.dispose);
      await _pump(tester, const DesktopCredentialsPage(), container);
      expect(
        find.text('删除'),
        findsOneWidget,
      ); // Default credential is protected.
      await tester.tap(find.byKey(const ValueKey('credential-edit-key1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('credential-name')),
        'Renamed',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('credential-password')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.widgetWithText(ManagementButton, '保存修改'));
      await tester.pumpAndSettle();
      expect(find.text('Save unavailable'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('credential-name')))
            .controller!
            .text,
        'Renamed',
      );
      expect(settings.credentials.single['password'], '');
      settings.fail = false;
      await tester.tap(find.widgetWithText(ManagementButton, '保存修改'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopCredentialDialog), findsNothing);
      expect(settings.credentials.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'script editor retries without losing command and default group',
    (tester) async {
      final api = _Api();
      final scripts = _Scripts()..fail = true;
      final container = _container(api, scripts: scripts);
      addTearDown(container.dispose);
      await _pump(tester, const DesktopScriptsPage(), container);
      await tester.tap(find.byKey(const Key('script-add')));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Health check');
      await tester.enterText(fields.at(2), 'uptime && df -h');
      await tester.tap(find.widgetWithText(ManagementButton, '创建脚本'));
      await tester.pumpAndSettle();
      expect(find.text('Save unavailable'), findsOneWidget);
      expect(scripts.created.single.group, 'default');
      expect(scripts.created.single.command, 'uptime && df -h');
      scripts.fail = false;
      await tester.tap(find.widgetWithText(ManagementButton, '创建脚本'));
      await tester.pumpAndSettle();
      expect(scripts.created.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('task enabled toggle preserves script from full detail', (
    tester,
  ) async {
    final api = _Api();
    final repo = _Scheduled();
    final container = _container(api, scheduled: repo);
    addTearDown(container.dispose);
    await _pump(tester, const DesktopScheduledTasksPage(), container);
    await tester.tap(find.byType(ManagementSwitch).first);
    await tester.pumpAndSettle();
    expect(repo.writes.single.enabled, false);
    expect(repo.writes.single.script.command, 'backup');
    expect(repo.writes.single.script.useBase64, true);
    expect(repo.writes.single.hostIds, ['host1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scheduled task creation retries with selected targets and Web defaults',
    (tester) async {
      final api = _Api();
      final repo = _Scheduled()..fail = true;
      final container = _container(api, scheduled: repo);
      addTearDown(container.dispose);
      await _pump(tester, const DesktopScheduledTasksPage(), container);
      await tester.tap(find.byKey(const Key('scheduled-task-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Nightly backup',
      );
      await tester.tap(find.byType(DesktopSelect).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Production').last);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final command = find.byType(TextFormField).last;
      await tester.ensureVisible(command);
      await tester.enterText(command, 'tar -czf /tmp/backup.tar.gz /etc');
      await tester.tap(find.widgetWithText(ManagementButton, '保存'));
      await tester.pumpAndSettle();
      expect(repo.writes.single.cron, '0 2 * * *');
      expect(repo.writes.single.timezone, 'Asia/Shanghai');
      expect(repo.writes.single.hostIds, ['host1']);
      expect(
        repo.writes.single.script.command,
        'tar -czf /tmp/backup.tar.gz /etc',
      );
      expect(find.byType(DesktopScheduledTaskDialog), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.widgetWithText(ManagementButton, '保存'));
      await tester.pumpAndSettle();
      expect(repo.writes.length, 2);
      expect(find.byType(DesktopScheduledTaskDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'task search, history filters and pagination retain Web interactions',
    (tester) async {
      final api = _Api();
      final scheduled = _Scheduled();
      final container = _container(api, scheduled: scheduled);
      addTearDown(container.dispose);
      await _pump(tester, const DesktopScheduledTasksPage(), container);
      final search = find.byKey(const Key('scheduled-task-search'));
      expect(tester.getSize(search).width, closeTo(324, 1));
      await tester.enterText(search, 'UTC');
      expect(scheduled.keywords, ['']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(scheduled.keywords.last, 'UTC');
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(scheduled.keywords.last, '');
      await tester.tap(find.text('执行历史'));
      await tester.pumpAndSettle();
      expect(find.text('暂无执行记录'), findsOneWidget);
      expect(find.widgetWithText(ManagementButton, '清空记录'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(scheduled.runQueries.last['page'], 2);
      await tester.tap(find.byKey(const Key('scheduled-history-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup'));
      await tester.pumpAndSettle();
      expect(scheduled.runQueries.last['taskId'], 'task1');
      expect(scheduled.runQueries.last['page'], 1);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('scheduled-history-task')),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduled.runQueries.last['taskId'], '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings mount lazily and retain unfinished forms between tabs',
    (tester) async {
      final api = _Api();
      final container = _container(api);
      addTearDown(container.dispose);
      await _pump(tester, const DesktopSettingsPage(), container);
      expect(api.reads, ['/mfa2-status']);
      await tester.enterText(find.byType(TextFormField).first, 'draft-user');
      await tester.tap(
        find.byKey(const ValueKey('desktop-settings-notifications')),
      );
      await tester.pumpAndSettle();
      expect(api.reads, contains('/notify-config'));
      await tester.tap(find.byKey(const ValueKey('desktop-settings-account')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'draft-user',
      );
      expect(api.reads.where((p) => p == '/mfa2-status').length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'five modules and seven settings fit minimum window ($english, $dark)',
        (tester) async {
          final api = _Api();
          final container = _container(api);
          addTearDown(container.dispose);
          for (final page in [
            const DesktopCredentialsPage(),
            const DesktopScriptsPage(),
            const DesktopBatchPage(),
            const DesktopScheduledTasksPage(),
            const DesktopSettingsPage(),
          ]) {
            await _pump(
              tester,
              page,
              container,
              locale: Locale(english ? 'en' : 'zh'),
              dark: dark,
              scale: 1.2,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType}',
            );
          }
          for (final section in DesktopSettingsSection.values) {
            container.read(desktopSettingsSectionProvider.notifier).state =
                section;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'Settings $section');
          }
        },
      );
    }
  }

  testWidgets('notification failure preserves secrets and permits retry', (
    tester,
  ) async {
    final api = _Api();
    final repo = _DesktopSettings(api)..fail = true;
    final container = _container(api, desktopSettings: repo);
    addTearDown(container.dispose);
    await _pump(
      tester,
      const SingleChildScrollView(child: DesktopNotificationSettings()),
      container,
    );
    await tester.tap(find.widgetWithText(ManagementButton, '测试并保存'));
    await tester.pumpAndSettle();
    expect(find.text('Test notification failed'), findsOneWidget);
    expect(repo.saved!['tg'], {'token': 'bot-token', 'chatId': '-100'});
    repo.fail = false;
    await tester.tap(find.widgetWithText(ManagementButton, '测试并保存'));
    await tester.pumpAndSettle();
    expect(find.text('测试通过，保存成功；请确认已收到测试通知。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI provider save retains unknown server fields and Web preference',
    (tester) async {
      final api = _Api();
      final repo = _Agent(api);
      final container = _container(api, agent: repo);
      addTearDown(container.dispose);
      await _pump(
        tester,
        const SingleChildScrollView(child: DesktopAiSettings()),
        container,
      );
      final models = find.byWidgetPredicate(
        (w) => w is DesktopSelect && w.allowCreate,
      );
      await tester.ensureVisible(models);
      await tester.tap(models);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('desktop-select-create')),
        'custom-model',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final increase = find.descendant(
        of: find.byType(DesktopSettingNumber).first,
        matching: find.byTooltip('增加'),
      );
      await tester.ensureVisible(increase);
      await tester.tap(increase);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(ManagementButton, '保存 Provider 设置');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saved!.toProviderJson()['legacyField'], 'retain');
      expect(repo.saved!.toProviderJson()['ui']['petEnabled'], false);
      expect(repo.saved!.models, ['model-a', 'custom-model']);
      expect(repo.saved!.contextLimit, 65536 + 1024);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Plus device refresh and release preserve current license at desktop sizes',
    (tester) async {
      final api = _Api(plusActive: true);
      final repo = _DesktopSettings(api);
      final container = _container(api, desktopSettings: repo);
      addTearDown(container.dispose);
      await _pump(
        tester,
        const SingleChildScrollView(child: DesktopPlusSettings()),
        container,
        width: 1440,
      );
      expect(find.text('本机'), findsOneWidget);
      expect(find.text('实例 abcd…'), findsOneWidget);
      expect(find.text('v3.0.1'), findsOneWidget);
      expect(find.text('5分钟前'), findsOneWidget);
      expect(repo.deviceReads, 1);
      await tester.tap(find.widgetWithText(TextButton, '刷新'));
      await tester.pumpAndSettle();
      expect(repo.deviceReads, 2);
      await tester.tap(find.widgetWithText(OutlinedButton, '释放'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ManagementButton, '确定'));
      await tester.pumpAndSettle();
      expect(repo.released, ['efgh-other']);
      expect(repo.deviceReads, 3);
      expect(find.text('已用 1 / 3 台'), findsOneWidget);
      expect(find.text('本机'), findsOneWidget);
      expect(find.text('v3.0.1'), findsNothing);
      for (final english in [false, true]) {
        await _pump(
          tester,
          const DesktopSettingsPage(),
          container,
          scale: 1.2,
          locale: Locale(english ? 'en' : 'zh'),
        );
        container.read(desktopSettingsSectionProvider.notifier).state =
            DesktopSettingsSection.plus;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('MCP editor validates endpoint and leaves failed form editable', (
    tester,
  ) async {
    final api = _Api();
    final container = _container(api);
    addTearDown(container.dispose);
    await _pump(tester, const DesktopMcpEditor(), container);
    await tester.tap(find.widgetWithText(ManagementButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 HTTP/HTTPS URL'), findsOneWidget);
    expect(find.byType(DesktopMcpEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
