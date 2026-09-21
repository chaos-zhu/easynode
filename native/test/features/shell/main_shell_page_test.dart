import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_repository.dart';
import 'package:easynode_native/features/settings/app_update_repository.dart';
import 'package:easynode_native/features/shell/main_shell_page.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/app_update_notifier.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:easynode_native/state/server_data_refresh.dart';
import 'package:easynode_native/state/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopAuthNotifier extends AuthNotifier {
  _NoopAuthNotifier(Ref ref) : super(ref, AuthState.empty);
}

class _NoopAppUpdateNotifier extends AppUpdateNotifier {
  _NoopAppUpdateNotifier(super.ref);

  @override
  Future<AppUpdateCheckResult?> check() async => null;
}

class _FakeScheduledTaskRepository implements ScheduledTaskRepository {
  @override
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''}) async =>
      const [];

  @override
  Future<ScheduledTask> fetchTask(String id) => throw UnimplementedError();

  @override
  Future<ScheduledTask> createTask(ScheduledTaskFormData form) =>
      throw UnimplementedError();

  @override
  Future<ScheduledTask> updateTask(ScheduledTaskFormData form) =>
      throw UnimplementedError();

  @override
  Future<void> deleteTask(String id) => throw UnimplementedError();

  @override
  Future<ScheduledTaskRun> runTask(String id) => throw UnimplementedError();

  @override
  Future<ScheduledTaskRunPage> fetchRuns({
    String? taskId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) => throw UnimplementedError();

  @override
  Future<ScheduledTaskRun> fetchRun(String id) => throw UnimplementedError();

  @override
  Future<void> stopRun(String id) => throw UnimplementedError();

  @override
  Future<({int batches, int targets})> clearRuns() =>
      throw UnimplementedError();
}

Future<Widget> _app() async {
  SharedPreferences.setMockInitialValues({'app.defaultTab': 'scheduledTasks'});
  final storage = AppStorage(await SharedPreferences.getInstance());
  return ProviderScope(
    overrides: [
      appStorageProvider.overrideWithValue(storage),
      authProvider.overrideWith((ref) => _NoopAuthNotifier(ref)),
      appUpdateProvider.overrideWith((ref) => _NoopAppUpdateNotifier(ref)),
      serverSharedDataBootstrapProvider.overrideWith((ref) async {}),
      scheduledTaskRepositoryProvider.overrideWithValue(
        _FakeScheduledTaskRepository(),
      ),
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
      home: const MainShellPage(),
    ),
  );
}

void main() {
  testWidgets('uses a drawer on phone widths', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-navigation-drawer')), findsNothing);

    await tester.flingFrom(const Offset(200, 420), const Offset(-180, 0), 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-navigation-drawer')), findsNothing);

    await tester.flingFrom(const Offset(200, 420), const Offset(180, 0), 800);
    await tester.pumpAndSettle();

    final drawer = find.byKey(const ValueKey('app-navigation-drawer'));
    expect(drawer, findsOneWidget);
    expect(tester.getSize(drawer).width, 272);
    expect(find.text('Scheduled tasks'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('uses collapsed and expanded rails at wider breakpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    var rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.selected);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();

    rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.labelType, NavigationRailLabelType.none);
  });

  testWidgets('keeps navigation rail usable in a short window', (tester) async {
    tester.view.physicalSize = const Size(800, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.scrollable, isTrue);
    expect(tester.takeException(), isNull);
  });
}
