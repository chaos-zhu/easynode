import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/features/servers/server_form_data.dart';
import 'package:easynode_native/features/servers/server_form_page.dart';
import 'package:easynode_native/features/servers/server_group_model.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_proxy_model.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:easynode_native/state/proxy_list_notifier.dart';

class _FakeRepository implements ServerRepository {
  int createCalls = 0;

  @override
  Future<List<ServerModel>> fetchHosts() async => const [];

  @override
  Future<List<ServerGroupModel>> fetchGroups() async => [
    ServerGroupModel.fromJson({
      'id': 'default',
      'name': 'Default group',
      'index': 1,
    }),
  ];

  @override
  Future<String> createHost(ServerFormData form) async {
    createCalls++;
    return 'success';
  }

  @override
  Future<String> updateHost(ServerFormData form) async => 'success';

  @override
  Future<String> deleteHost(String hostId) async => 'success';

  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId) async =>
      const [];
}

class _DelayedProxyListNotifier extends ProxyListNotifier {
  _DelayedProxyListNotifier(this.result);

  final Future<List<ServerProxyModel>> result;

  @override
  Future<List<ServerProxyModel>> build() => result;
}

Widget _wrap(
  ServerRepository repo, {
  ServerModel? server,
  ProxyListNotifier Function()? proxyList,
}) {
  return ProviderScope(
    overrides: [
      serverRepositoryProvider.overrideWithValue(repo),
      isPlusActiveProvider.overrideWithValue(true),
      if (proxyList != null) proxyListProvider.overrideWith(proxyList),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ServerFormPage(server: server),
    ),
  );
}

Future<void> _pumpForm(WidgetTester tester, _FakeRepository repo) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(repo));
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'prod');
  await tester.enterText(fields.at(2), '10.0.0.2');
}

void main() {
  testWidgets('requires credential when auth type is credential', (
    tester,
  ) async {
    final repo = _FakeRepository();
    await _pumpForm(tester, repo);
    await _fillRequiredFields(tester);

    await tester.tap(find.text('Credential').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server').last);
    await tester.pumpAndSettle();

    expect(find.text('Select a credential'), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('requires proxy target when proxy type is not none', (
    tester,
  ) async {
    final repo = _FakeRepository();
    await _pumpForm(tester, repo);
    await _fillRequiredFields(tester);

    await tester.ensureVisible(find.text('Proxy').first);
    await tester.tap(find.text('Proxy').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server').last);
    await tester.pumpAndSettle();

    expect(find.text('Select a proxy service'), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('keeps existing proxy while proxy list is loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final proxyResult = Completer<List<ServerProxyModel>>();
    final server = ServerModel.fromJson({
      'id': 'server-1',
      'name': 'Production',
      'host': '10.0.0.2',
      'port': 22,
      'username': 'root',
      'authType': 'password',
      'connectType': 'ssh',
      'group': 'default',
      'index': 1,
      'proxyType': 'proxyServer',
      'proxyServer': 'proxy-1',
      'isConfig': true,
    });

    await tester.pumpWidget(
      _wrap(
        _FakeRepository(),
        server: server,
        proxyList: () => _DelayedProxyListNotifier(proxyResult.future),
      ),
    );
    await tester.pump();

    expect(find.text('Office proxy'), findsNothing);

    proxyResult.complete([
      const ServerProxyModel(
        id: 'proxy-1',
        name: 'Office proxy',
        type: 'socks5',
        host: '127.0.0.1',
        port: 1080,
        username: '',
        password: '',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Office proxy'), findsOneWidget);
  });
}
