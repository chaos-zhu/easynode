import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_models.dart';
import 'package:easynode_native/features/scheduled_tasks/scheduled_task_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Request {
  const _Request(this.method, this.path, this.data, this.query);

  final String method;
  final String path;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? query;
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
    : super(
        serverAddress: 'https://panel.example.com',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  final requests = <_Request>[];
  final responses = <Map<String, dynamic>>[];

  Map<String, dynamic> _respond(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) {
    requests.add(_Request(method, path, data, query));
    return responses.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => _respond('GET', path, query: queryParameters);

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async => _respond('POST', path, data: data);

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) async => _respond('PUT', path, data: data);

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => _respond('DELETE', path, query: queryParameters);
}

Map<String, dynamic> _taskJson({String id = 'task-1'}) => {
  'id': id,
  'name': 'Backup',
  'enabled': true,
  'hostIds': ['host-1'],
  'cron': '0 0 * * *',
  'timezone': 'Asia/Shanghai',
  'timeoutSeconds': 120,
  'script': {'type': 'inline', 'command': 'uptime', 'useBase64': false},
  'notificationPolicy': 'failure',
};

void main() {
  test('maps task CRUD and immediate execution endpoints', () async {
    final api = _FakeApiClient();
    final repository = ApiScheduledTaskRepository(apiClient: api);
    final form = ScheduledTaskFormData.create()
      ..name = 'Backup'
      ..hostIds = ['host-1']
      ..script = const ScheduledTaskScript(type: 'inline', command: 'uptime');
    api.responses.addAll([
      {
        'data': [_taskJson()],
      },
      {'data': _taskJson()},
      {'data': _taskJson()},
      {
        'data': {
          'id': 'run-1',
          'taskId': 'task-1',
          'taskName': 'Backup',
          'trigger': 'manual',
          'status': 'running',
          'targetCount': 1,
        },
      },
    ]);

    await repository.fetchTasks(keyword: 'back');
    final created = await repository.createTask(form);
    form.id = created.id;
    await repository.updateTask(form);
    final run = await repository.runTask(created.id);

    expect(run.id, 'run-1');
    expect(api.requests.map((request) => request.path), [
      '/scheduled-tasks',
      '/scheduled-tasks',
      '/scheduled-tasks/task-1',
      '/scheduled-tasks/task-1/run',
    ]);
    expect(api.requests.first.query, {'keyword': 'back'});
    expect(api.requests[1].data?['script'], {
      'type': 'inline',
      'command': 'uptime',
      'useBase64': false,
    });
  });

  test('maps history filters, stop, and clear responses', () async {
    final api = _FakeApiClient();
    final repository = ApiScheduledTaskRepository(apiClient: api);
    api.responses.addAll([
      {
        'data': {'items': <Object>[], 'total': 0, 'page': 2, 'pageSize': 20},
      },
      {'data': true},
      {
        'data': {'batchesRemoved': 3, 'targetsRemoved': 5},
      },
    ]);

    await repository.fetchRuns(taskId: 'task-1', status: 'failed', page: 2);
    await repository.stopRun('run-1');
    final removed = await repository.clearRuns();

    expect(api.requests.first.query, {
      'taskId': 'task-1',
      'status': 'failed',
      'page': 2,
      'pageSize': 20,
    });
    expect(api.requests[1].path, '/scheduled-task-runs/run-1/stop');
    expect(api.requests[2].method, 'DELETE');
    expect(api.requests[2].path, '/scheduled-task-runs');
    expect(removed.batches, 3);
    expect(removed.targets, 5);
  });
}
