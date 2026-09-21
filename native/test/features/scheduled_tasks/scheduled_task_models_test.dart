import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses task list metadata and millisecond timestamps', () {
    final task = ScheduledTask.fromJson({
      'id': 'task-1',
      'name': 'Backup',
      'enabled': true,
      'hostIds': ['host-1', 'host-2'],
      'cron': '0 0 * * *',
      'timezone': 'Asia/Shanghai',
      'timeoutSeconds': 300,
      'script': {'type': 'inline', 'useBase64': true},
      'notificationPolicy': 'always',
      'nextRunAt': 1700000000000,
      'nextRunTimes': [1700000000000, 1700086400000],
      'lastRunStatus': 'success',
    });

    expect(task.id, 'task-1');
    expect(task.hostIds, ['host-1', 'host-2']);
    expect(task.script.command, isEmpty);
    expect(task.script.useBase64, isTrue);
    expect(task.nextRunAt?.millisecondsSinceEpoch, 1700000000000);
    expect(task.nextRunTimes, hasLength(2));
  });

  test('serializes inline and referenced scripts with the server contract', () {
    final inline = ScheduledTaskFormData.create()
      ..name = '  deploy  '
      ..hostIds = ['host-1']
      ..cron = ' */30 * * * * '
      ..script = const ScheduledTaskScript(
        type: 'inline',
        command: 'echo deploy',
        useBase64: true,
      );
    final inlineJson = inline.toJson();

    expect(inlineJson['name'], 'deploy');
    expect(inlineJson['cron'], '*/30 * * * *');
    expect(inlineJson['script'], {
      'type': 'inline',
      'command': 'echo deploy',
      'useBase64': true,
    });

    inline.script = const ScheduledTaskScript(
      type: 'library',
      scriptId: 'script-1',
    );
    expect(inline.toJson()['script'], {
      'type': 'library',
      'scriptId': 'script-1',
    });
  });

  test('parses run target output and timeout details', () {
    final run = ScheduledTaskRun.fromJson({
      'id': 'run-1',
      'taskId': 'task-1',
      'taskName': 'Backup',
      'trigger': 'manual',
      'status': 'timeout',
      'targetCount': 1,
      'durationMs': 120000,
      'targets': [
        {
          'id': 'target-1',
          'hostId': 'host-1',
          'hostName': 'node-1',
          'status': 'timeout',
          'stdout': 'partial output',
          'stderr': '',
          'error': '执行阶段超时',
          'timeoutPhase': 'execution',
          'truncated': true,
        },
      ],
    });

    expect(run.isRunning, isFalse);
    expect(run.targets.single.stdout, 'partial output');
    expect(run.targets.single.timeoutPhase, 'execution');
    expect(run.targets.single.truncated, isTrue);
  });

  test('classifies terminal statuses and formats task timezone', () {
    ScheduledTaskRun runWithStatus(String status) => ScheduledTaskRun.fromJson({
      'id': 'run-1',
      'taskId': 'task-1',
      'taskName': 'Backup',
      'trigger': 'manual',
      'status': status,
      'targetCount': 1,
    });

    expect(runWithStatus('running').isComplete, isFalse);
    expect(runWithStatus('cancelling').isComplete, isFalse);
    for (final status in [
      'success',
      'partial',
      'failed',
      'timeout',
      'cancelled',
      'skipped',
      'interrupted',
    ]) {
      expect(runWithStatus(status).isComplete, isTrue, reason: status);
    }

    final summerInstant = DateTime.utc(2026, 7, 1, 12);
    expect(
      formatTaskDate(summerInstant, timezoneName: 'Asia/Shanghai'),
      '2026-07-01 20:00:00',
    );
    expect(
      formatTaskDate(summerInstant, timezoneName: 'America/New_York'),
      '2026-07-01 08:00:00',
    );
  });
}
