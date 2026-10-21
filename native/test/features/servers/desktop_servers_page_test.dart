import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/ui/desktop_select.dart';
import 'package:easynode_native/features/order/order_layout.dart';
import 'package:easynode_native/features/servers/desktop_server_form_dialog.dart';
import 'package:easynode_native/features/servers/desktop_servers_page.dart';
import 'package:easynode_native/features/servers/server_form_data.dart';
import 'package:easynode_native/features/servers/server_credential_model.dart';
import 'package:easynode_native/features/servers/server_proxy_model.dart';
import 'package:easynode_native/features/servers/server_group_model.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/features/settings/models/plus_info.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/credential_list_notifier.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:easynode_native/state/proxy_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends ServerRepository {
  _Repository({bool withHost = false}) {
    if (withHost) {
      hosts.add(
        ServerModel.fromJson({
          'id': 'host-1',
          'name': 'Production',
          'host': '10.0.0.2',
          'port': 22,
          'username': 'root',
          'authType': 'password',
          'connectType': 'ssh',
          'group': 'default',
          'isConfig': true,
        }),
      );
    }
  }

  final hosts = <ServerModel>[];
  final creates = <Map<String, dynamic>>[];
  final updates = <Map<String, dynamic>>[];
  final deletions = <String>[];
  int catalogReads = 0;
  String? saveError;
  String? deleteError;

  @override
  Future<HostCatalog> fetchCatalog() async {
    catalogReads++;
    return HostCatalog(
      hosts: await fetchHosts(),
      groups: await fetchGroups(),
      order: OrderLayout(
        schemaVersion: 1,
        revision: 0,
        sections: [
          OrderSection(
            groupId: 'default',
            itemIds: hosts.map((host) => host.id).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Future<List<ServerModel>> fetchHosts() async => [...hosts];

  @override
  Future<List<ServerGroupModel>> fetchGroups() async => const [
    ServerGroupModel(id: 'default', name: 'Default'),
    ServerGroupModel(id: 'staging', name: 'Staging'),
  ];

  @override
  Future<String> createHost(ServerFormData form) async {
    creates.add(form.toJson());
    if (saveError != null) throw ApiFailure(saveError!);
    hosts.add(ServerModel.fromJson({...form.toJson(), 'id': 'host-1'}));
    return 'success';
  }

  @override
  Future<String> updateHost(ServerFormData form) async {
    updates.add(form.toJson());
    if (saveError != null) throw ApiFailure(saveError!);
    hosts[hosts.indexWhere((host) => host.id == form.id)] =
        ServerModel.fromJson(form.toJson());
    return 'success';
  }

  @override
  Future<String> deleteHost(String hostId) async {
    deletions.add(hostId);
    if (deleteError != null) throw ApiFailure(deleteError!);
    hosts.removeWhere((host) => host.id == hostId);
    return 'success';
  }

  // Any unexpected connection/favorite request fails the test.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

class _Plus extends PlusInfoNotifier {
  @override
  Future<PlusInfo> build() async => PlusInfo.fromJson({'active': true});
}

class _Credentials extends CredentialListNotifier {
  @override
  Future<List<ServerCredentialModel>> build() async => const [
    ServerCredentialModel(
      id: 'cred-1',
      name: 'Deploy key',
      authType: 'privateKey',
    ),
  ];
}

class _Proxies extends ProxyListNotifier {
  @override
  Future<List<ServerProxyModel>> build() async => [
    ServerProxyModel.fromJson({
      'id': 'proxy-1',
      'name': 'Office proxy',
      'type': 'socks5',
    }),
  ];
}

Future<void> _pumpPage(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverRepositoryProvider.overrideWithValue(repository),
        plusInfoProvider.overrideWith(_Plus.new),
        credentialListProvider.overrideWith(_Credentials.new),
        proxyListProvider.overrideWith(_Proxies.new),
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
        home: const Scaffold(body: DesktopServersPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String name) => find.byKey(ValueKey('desktop-server-form-$name'));

Future<void> _add(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('desktop-servers-add')));
  await tester.pumpAndSettle();
  await tester.enterText(_field('name'), 'Production');
  await tester.enterText(_field('host'), '10.0.0.2');
}

Future<void> _action(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('desktop-server-actions-host-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('desktop-server-form-save')));
  await tester.pumpAndSettle();
}

Future<void> _importKey(WidgetTester tester) async {
  final button = tester.widget<TextButton>(
    find.byKey(const Key('desktop-server-import-key')),
  );
  // Await the UI callback inside runAsync so the real fixture file read finishes.
  await tester.runAsync(button.onPressed! as Future<void> Function());
  await tester.pumpAndSettle();
}

void main() {
  group('private key file import', () {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    const filesChannel = MethodChannel('easynode/files');
    const keyText =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nfixture\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
    late FilePickerPlatform previousPicker;
    late Directory directory;
    late File keyFile;
    late File invalidFile;

    setUp(() async {
      previousPicker = FilePickerPlatform.instance;
      FilePickerMacOS.registerWith();
      directory = await Directory.systemTemp.createTemp('easynode-key-import-');
      keyFile = await File(
        '${directory.path}/id_ed25519',
      ).writeAsString(keyText);
      invalidFile = await File(
        '${directory.path}/invalid',
      ).writeAsBytes([0xff, 0xfe]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filesChannel, (call) async {
            expect(call.method, 'getHomeDirectory');
            return '/Users/easynode-fixture';
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pickFiles');
            if (Platform.isMacOS) {
              expect(
                call.arguments['initialDirectory'],
                '/Users/easynode-fixture/.ssh',
              );
            }
            return [keyFile.path];
          });
    });

    tearDown(() async {
      FilePickerPlatform.instance = previousPicker;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filesChannel, null);
      await directory.delete(recursive: true);
    });

    Future<void> openForm(WidgetTester tester, {bool edit = false}) async {
      await _pumpPage(tester, _Repository(withHost: edit));
      if (edit) {
        await _action(tester, 'Edit configuration');
      } else {
        await _add(tester);
      }
      await tester.tap(find.text('Private key'));
      await tester.pumpAndSettle();
    }

    for (final edit in [false, true]) {
      testWidgets(
        'reads a UTF-8 private key path in ${edit ? 'edit' : 'add'} form',
        (tester) async {
          await openForm(tester, edit: edit);
          await _importKey(tester);
          expect(
            tester.widget<TextFormField>(_field('privateKey')).controller!.text,
            keyText,
          );
          expect(
            find.text('Could not open the file picker. Please retry.'),
            findsNothing,
          );
        },
      );
    }

    testWidgets(
      'cancel preserves the current key without reporting a file error',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        await openForm(tester);
        await tester.enterText(_field('privateKey'), 'existing-input');
        await _importKey(tester);
        expect(
          tester.widget<TextFormField>(_field('privateKey')).controller!.text,
          'existing-input',
        );
        expect(
          find.text(
            'Could not read the private key. Check file permissions and retry.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'reports picker permissions accurately and clears the error after retry',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              throw PlatformException(code: 'ENTITLEMENT_NOT_FOUND');
            });
        await openForm(tester);
        await _importKey(tester);
        expect(
          find.text(
            'Could not open the file picker: the app is missing file access permissions.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('The private key file is not valid UTF-8 text.'),
          findsNothing,
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => [keyFile.path]);
        await _importKey(tester);
        expect(
          tester.widget<TextFormField>(_field('privateKey')).controller!.text,
          keyText,
        );
        expect(
          find.text(
            'Could not open the file picker: the app is missing file access permissions.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets('invalid UTF-8 is reported without replacing the current key', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => [invalidFile.path]);
      await openForm(tester);
      await tester.enterText(_field('privateKey'), 'existing-input');
      await _importKey(tester);
      expect(
        find.text('The private key file is not valid UTF-8 text.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(_field('privateKey')).controller!.text,
        'existing-input',
      );
    });

    testWidgets(
      'file read failure is distinct from encoding and picker errors',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => ['${directory.path}/missing-key'],
            );
        await openForm(tester);
        await _importKey(tester);
        expect(
          find.text(
            'Could not read the private key. Check file permissions and retry.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('The private key file is not valid UTF-8 text.'),
          findsNothing,
        );
      },
    );
  });

  testWidgets(
    'clicking the host copies its exact address without editing or selecting',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final repository = _Repository(withHost: true);
      await _pumpPage(tester, repository);
      await tester.tap(
        find.byKey(const ValueKey('desktop-server-host-host-1')),
      );
      await tester.pumpAndSettle();
      expect(copied, '10.0.0.2');
      expect(find.text('Host address copied'), findsOneWidget);
      expect(find.byType(DesktopServerFormDialog), findsNothing);
      expect(find.text('1 instances selected'), findsNothing);
      expect(repository.updates, isEmpty);
      expect(repository.catalogReads, 1);
    },
  );

  testWidgets('clipboard failure reports an error without opening the editor', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_unavailable');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpPage(tester, _Repository(withHost: true));
    await tester.tap(find.byKey(const ValueKey('desktop-server-host-host-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not copy the host address. Please retry.'),
      findsOneWidget,
    );
    expect(find.byType(DesktopServerFormDialog), findsNothing);
  });

  testWidgets('creates an instance and refreshes only the desktop catalog', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpPage(tester, repository);
    final addButton = tester.widget<FilledButton>(
      find.byKey(const Key('desktop-servers-add')),
    );
    expect(
      addButton.style!.backgroundColor!.resolve({}),
      AppColorTheme.defaultLight.accent,
    );
    await _add(tester);
    await tester.enterText(_field('password'), 'new-secret');
    await _save(tester);

    expect(repository.creates.single['password'], 'new-secret');
    expect(repository.creates.single['port'], 22);
    expect(repository.creates.single['group'], 'default');
    expect(repository.catalogReads, 2);
    expect(find.byType(DesktopServerFormDialog), findsNothing);
    expect(find.text('Production'), findsOneWidget);
  });

  testWidgets(
    'custom group, credential and proxy selects submit their record IDs',
    (tester) async {
      final repository = _Repository();
      await _pumpPage(tester, repository);
      await _add(tester);
      await tester.tap(find.byType(DesktopSelect));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('desktop-select-options')),
          matching: find.byKey(const ValueKey('staging')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credential'));
      await tester.pumpAndSettle();
      final credential = find.byWidgetPredicate(
        (widget) =>
            widget is DesktopSelect && widget.options.containsKey('cred-1'),
      );
      await tester.tap(credential);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deploy key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Proxy server').last);
      await tester.tap(find.text('Proxy server').last);
      await tester.pumpAndSettle();
      final proxy = find.byWidgetPredicate(
        (widget) =>
            widget is DesktopSelect && widget.options.containsKey('proxy-1'),
      );
      await tester.ensureVisible(proxy);
      await tester.tap(proxy);
      await tester.pumpAndSettle();
      expect(find.text('SOCKS5'), findsOneWidget);
      await tester.tap(find.text('Office proxy'));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repository.creates.single['group'], 'staging');
      expect(repository.creates.single['credential'], 'cred-1');
      expect(repository.creates.single['proxyType'], 'proxyServer');
      expect(repository.creates.single['proxyServer'], 'proxy-1');
    },
  );

  testWidgets(
    'inline date, reminder and tags keep their values when advanced settings collapse',
    (tester) async {
      final repository = _Repository();
      await _pumpPage(tester, repository);
      await _add(tester);
      await tester.tap(find.text('Other settings'));
      await tester.pumpAndSettle();
      final expiry = find.byKey(const Key('desktop-server-expiry'));
      final reminder = find.byKey(const Key('desktop-server-expiry-notify'));
      expect(reminder, findsNothing);

      Future<DateTime> pickDate() async {
        await tester.ensureVisible(expiry);
        await tester.tap(expiry);
        await tester.pumpAndSettle();
        final calendar = tester.widget<CalendarDatePicker>(
          find.byType(CalendarDatePicker),
        );
        final date = DateTime(
          calendar.initialDate!.year,
          calendar.initialDate!.month,
          15,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(CalendarDatePicker),
            matching: find.text('15'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CalendarDatePicker), findsNothing);
        return date;
      }

      await pickDate();
      await tester.ensureVisible(reminder);
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear expiry date'));
      await tester.pumpAndSettle();
      expect(reminder, findsNothing);
      final date = await pickDate();
      await tester.ensureVisible(reminder);
      await tester.tap(reminder);
      final tags = find.byKey(const Key('desktop-server-form-tags'));
      await tester.ensureVisible(tags);
      await tester.enterText(tags, 'ops,production');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('ops'), findsOneWidget);
      expect(find.text('production'), findsOneWidget);
      expect(tester.widget<TextField>(tags).controller!.text, isEmpty);
      expect(tester.widget<TextField>(tags).focusNode!.hasFocus, isTrue);
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('ops'), matching: find.byType(Row))
              .first,
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(tags, 'production,canary');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(find.text('production'), findsOneWidget);
      expect(find.text('canary'), findsOneWidget);
      await tester.enterText(tags, 'manual');
      await tester.tap(find.byKey(const Key('desktop-server-add-tag')));
      await tester.pumpAndSettle();
      expect(find.text('manual'), findsOneWidget);
      expect(tester.widget<TextField>(tags).focusNode!.hasFocus, isTrue);
      await tester.enterText(tags, 'pending');
      await tester.ensureVisible(find.text('Other settings'));
      await tester.tap(find.text('Other settings'));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repository.creates.single['expired'], date.millisecondsSinceEpoch);
      expect(repository.creates.single['expiredNotify'], isTrue);
      expect(repository.creates.single['tag'], [
        'production',
        'canary',
        'manual',
        'pending',
      ]);
    },
  );

  testWidgets(
    'editing metadata submits a blank secret to retain the saved one',
    (tester) async {
      final repository = _Repository(withHost: true);
      await _pumpPage(tester, repository);
      await tester.tap(
        find.byKey(const ValueKey('desktop-server-name-host-1')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_field('password')).controller!.text,
        '',
      );
      final passwordDecoration = tester
          .widget<TextField>(
            find.descendant(
              of: _field('password'),
              matching: find.byType(TextField),
            ),
          )
          .decoration!;
      expect(
        passwordDecoration.hintText,
        'Leave blank to keep the existing saved secret.',
      );
      expect(passwordDecoration.helperText, isNull);
      await tester.enterText(_field('name'), 'Production renamed');
      await _save(tester);

      expect(repository.updates.single['id'], 'host-1');
      expect(repository.updates.single['password'], '');
      expect(repository.updates.single['authType'], 'password');
      expect(find.text('Production renamed'), findsOneWidget);
      expect(repository.catalogReads, 2);
    },
  );

  testWidgets(
    'changing authentication requires a replacement and excludes inactive secrets',
    (tester) async {
      final repository = _Repository(withHost: true);
      await _pumpPage(tester, repository);
      await _action(tester, 'Edit configuration');
      await tester.enterText(_field('password'), 'discard-this-password');
      await tester.tap(find.text('Private key'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(repository.updates, isEmpty);
      expect(
        find.text(
          'Enter a new password or private key when changing authentication.',
        ),
        findsOneWidget,
      );
      await tester.enterText(_field('privateKey'), 'replacement-private-key');
      await _save(tester);

      expect(repository.updates.single['authType'], 'privateKey');
      expect(
        repository.updates.single['privateKey'],
        'replacement-private-key',
      );
      expect(repository.updates.single['password'], '');
      expect(repository.updates.single['credential'], '');
    },
  );

  testWidgets('a failed save retains the form and supports retry', (
    tester,
  ) async {
    final repository = _Repository()..saveError = 'Save unavailable';
    await _pumpPage(tester, repository);
    await _add(tester);
    await _save(tester);

    expect(find.byType(DesktopServerFormDialog), findsOneWidget);
    expect(find.text('Save unavailable'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_field('name')).controller!.text,
      'Production',
    );
    expect(repository.catalogReads, 1);
    repository.saveError = null;
    await _save(tester);
    expect(find.byType(DesktopServerFormDialog), findsNothing);
    expect(find.text('Production'), findsOneWidget);
  });

  testWidgets('delete requires confirmation and supports retry after failure', (
    tester,
  ) async {
    final repository = _Repository(withHost: true)
      ..deleteError = 'Delete unavailable';
    await _pumpPage(tester, repository);
    await _action(tester, 'Delete instance');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deletions, isEmpty);

    await _action(tester, 'Delete instance');
    await tester.tap(find.byKey(const Key('desktop-server-delete-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text('Failed to delete server: Delete unavailable'),
      findsOneWidget,
    );
    expect(repository.catalogReads, 1);
    expect(find.text('Production'), findsOneWidget);

    repository.deleteError = null;
    await tester.tap(find.byKey(const Key('desktop-server-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repository.deletions, ['host-1', 'host-1']);
    expect(repository.catalogReads, 2);
    expect(find.text('Production'), findsNothing);
    expect(find.text('No instances yet'), findsOneWidget);
  });
}
