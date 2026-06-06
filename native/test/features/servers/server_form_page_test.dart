import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_form_data.dart';
import 'package:mobile/features/servers/server_form_page.dart';
import 'package:mobile/features/servers/server_group_model.dart';
import 'package:mobile/features/servers/server_model.dart';
import 'package:mobile/features/servers/server_repository.dart';
import 'package:mobile/features/shell/sftp_session_manager.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/state/api_providers.dart';

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

Widget _wrap(ServerRepository repo) {
  return ProviderScope(
    overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ServerFormPage(),
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
}
