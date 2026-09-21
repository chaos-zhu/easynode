import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_repository.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_run_detail_page.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PollingRepository implements ScheduledTaskRepository {
  int fetchCalls = 0;

  ScheduledTaskRun _run(String status) => ScheduledTaskRun.fromJson({
    'id': 'run-1',
    'taskId': 'task-1',
    'taskName': 'Backup',
    'trigger': 'manual',
    'status': status,
    'targetCount': 1,
  });

  @override
  Future<ScheduledTaskRun> fetchRun(String id) async {
    fetchCalls++;
    if (fetchCalls == 1) return _run('running');
    if (fetchCalls == 2) throw Exception('temporary network failure');
    return _run('success');
  }

  @override
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''}) =>
      throw UnimplementedError();

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
  Future<void> stopRun(String id) => throw UnimplementedError();

  @override
  Future<({int batches, int targets})> clearRuns() =>
      throw UnimplementedError();
}

Widget _app(ScheduledTaskRepository repository) => ProviderScope(
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
    home: const ScheduledTaskRunDetailPage(runId: 'run-1'),
  ),
);

void main() {
  testWidgets('polls incomplete runs every three seconds after an error', (
    tester,
  ) async {
    final repository = _PollingRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    expect(repository.fetchCalls, 1);
    expect(find.text('Running'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(repository.fetchCalls, 2);
    expect(find.text('Running'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(repository.fetchCalls, 3);
    expect(find.text('Success'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(repository.fetchCalls, 3);
  });
}
