import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_form_page.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scripts/script_model.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/host_list_notifier.dart';
import 'package:easynode_native/state/script_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _HostFixture extends HostListNotifier {
  @override
  Future<List<ServerModel>> build() async => [
    ServerModel.fromJson({
      'id': 'legacy-host',
      'name': 'Legacy host',
      'host': '10.0.0.8',
      'port': 22,
      'username': 'root',
      'connectType': 'ssh',
      'authType': 'password',
      'isConfig': false,
    }),
    ServerModel.fromJson({
      'id': 'active-host',
      'name': 'Active host',
      'host': '10.0.0.9',
      'port': 22,
      'username': 'root',
      'connectType': 'ssh',
      'authType': 'password',
      'isConfig': true,
    }),
  ];
}

class _ScriptFixture extends ScriptListNotifier {
  @override
  Future<List<ScriptModel>> build() async => const [];
}

Widget _app(ScheduledTask task) => ProviderScope(
  overrides: [
    hostListProvider.overrideWith(_HostFixture.new),
    scriptListProvider.overrideWith(_ScriptFixture.new),
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
    home: ScheduledTaskFormPage(task: task),
  ),
);

void main() {
  testWidgets('shows a selected unavailable host and allows removing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final task = ScheduledTask.fromJson({
      'id': 'task-1',
      'name': 'Backup',
      'enabled': true,
      'hostIds': ['legacy-host'],
      'cron': '0 0 * * *',
      'timezone': 'Asia/Shanghai',
      'timeoutSeconds': 120,
      'script': {'type': 'inline', 'command': 'uptime'},
      'notificationPolicy': 'failure',
    });

    await tester.pumpWidget(_app(task));
    await tester.pumpAndSettle();
    expect(find.text('Legacy host'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('Legacy host'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      visibleText.any(
        (text) =>
            text.startsWith('Unavailable; remove it before saving changes'),
      ),
      isTrue,
    );

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Legacy host'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Select target hosts'), findsOneWidget);

    await tester.drag(
      find.byType(ListView).hitTestable().first,
      const Offset(0, -550),
    );
    await tester.pumpAndSettle();
    final importButtonLabel = find.text('Import from library').hitTestable();
    expect(importButtonLabel, findsOneWidget);
    expect(
      find.ancestor(of: importButtonLabel, matching: find.byType(Wrap)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
