import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_repository.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_tasks_tab.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScheduledTaskRepository implements ScheduledTaskRepository {
  int runCalls = 0;

  static final task = ScheduledTask.fromJson({
    'id': 'task-1',
    'name': 'Nightly backup',
    'enabled': true,
    'hostIds': ['host-1'],
    'cron': '0 0 * * *',
    'timezone': 'Asia/Shanghai',
    'timeoutSeconds': 120,
    'script': {'type': 'library', 'scriptId': 'script-1'},
    'notificationPolicy': 'failure',
    'lastRunStatus': 'success',
  });

  static final completedRun = ScheduledTaskRun.fromJson({
    'id': 'run-1',
    'taskId': 'task-1',
    'taskName': 'Nightly backup',
    'trigger': 'manual',
    'status': 'success',
    'targetCount': 1,
    'durationMs': 250,
  });

  @override
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''}) async => [task];

  @override
  Future<ScheduledTask> fetchTask(String id) async => task;

  @override
  Future<ScheduledTask> createTask(ScheduledTaskFormData form) async => task;

  @override
  Future<ScheduledTask> updateTask(ScheduledTaskFormData form) async => task;

  @override
  Future<void> deleteTask(String id) async {}

  @override
  Future<ScheduledTaskRun> runTask(String id) async {
    runCalls++;
    return completedRun;
  }

  @override
  Future<ScheduledTaskRunPage> fetchRuns({
    String? taskId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async => ScheduledTaskRunPage(
    items: const [],
    total: 0,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<ScheduledTaskRun> fetchRun(String id) async => completedRun;

  @override
  Future<void> stopRun(String id) async {}

  @override
  Future<({int batches, int targets})> clearRuns() async =>
      (batches: 0, targets: 0);
}

Widget _wrap(ScheduledTaskRepository repository) {
  return ProviderScope(
    overrides: [scheduledTaskRepositoryProvider.overrideWithValue(repository)],
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
      home: const ScheduledTasksTab(),
    ),
  );
}

Future<void> _revealTaskActions(WidgetTester tester, String taskId) async {
  await tester.drag(
    find.byKey(ValueKey('scheduled-task-swipe-$taskId')),
    const Offset(-220, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups search and history under the more actions menu', (
    tester,
  ) async {
    final repository = _FakeScheduledTaskRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    final headerMenu = find.descendant(
      of: find.byKey(const ValueKey('scheduled-task-more-menu')),
      matching: find.byType(PopupMenuButton<String>),
    );
    expect(find.byTooltip('New scheduled task'), findsOneWidget);
    expect(headerMenu, findsOneWidget);
    expect(find.byTooltip('Search'), findsNothing);
    expect(find.byTooltip('Execution history'), findsNothing);

    await tester.tap(headerMenu);
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Execution history'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('scheduled-task-search-field')),
      findsOneWidget,
    );
    expect(find.text('Search name, cron, or timezone'), findsOneWidget);
  });

  testWidgets('toggles task details on tap and reveals actions on swipe', (
    tester,
  ) async {
    final repository = _FakeScheduledTaskRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Nightly backup'), findsOneWidget);
    expect(find.text('0 0 * * *'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('1 hosts'), findsNothing);
    expect(find.byTooltip('Run now'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('scheduled-task-task-1')),
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
    );

    final summary = find.byKey(const ValueKey('scheduled-task-summary-task-1'));
    await tester.tap(summary);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('scheduled-task-details-task-1')),
      findsOneWidget,
    );
    expect(find.text('1 hosts'), findsOneWidget);
    expect(find.text('Reference library script'), findsOneWidget);
    expect(find.byTooltip('Execution history'), findsOneWidget);
    expect(find.byTooltip('Run now'), findsOneWidget);

    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scheduled-task-details-task-1')),
      findsNothing,
    );

    await _revealTaskActions(tester, 'task-1');
    expect(
      find
          .byKey(const ValueKey('scheduled-task-action-edit-task-1'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find
          .byKey(const ValueKey('scheduled-task-action-delete-task-1'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scheduled-task-action-details-task-1')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('scheduled-task-swipe-task-1')),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(summary);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('scheduled-task-details-task-1')),
      findsOneWidget,
    );
    expect(find.text('1 hosts'), findsOneWidget);
    expect(find.text('Reference library script'), findsOneWidget);
    expect(find.byTooltip('Execution history'), findsOneWidget);
    expect(find.byTooltip('Run now'), findsOneWidget);

    await tester.tap(find.byTooltip('Run now'));
    await tester.pumpAndSettle();

    expect(repository.runCalls, 1);
    expect(find.text('Execution details'), findsOneWidget);
    expect(find.text('Nightly backup'), findsOneWidget);
  });
}
