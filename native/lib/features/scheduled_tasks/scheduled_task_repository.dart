import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import 'scheduled_task_models.dart';

abstract class ScheduledTaskRepository {
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''});
  Future<ScheduledTask> fetchTask(String id);
  Future<ScheduledTask> createTask(ScheduledTaskFormData form);
  Future<ScheduledTask> updateTask(ScheduledTaskFormData form);
  Future<void> deleteTask(String id);
  Future<ScheduledTaskRun> runTask(String id);
  Future<ScheduledTaskRunPage> fetchRuns({
    String? taskId,
    String? status,
    int page = 1,
    int pageSize = 20,
  });
  Future<ScheduledTaskRun> fetchRun(String id);
  Future<void> stopRun(String id);
  Future<({int batches, int targets})> clearRuns();
}

class ApiScheduledTaskRepository implements ScheduledTaskRepository {
  ApiScheduledTaskRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<List<ScheduledTask>> fetchTasks({String keyword = ''}) async {
    final response = await _api.getJson(
      '/scheduled-tasks',
      queryParameters: keyword.trim().isEmpty
          ? null
          : {'keyword': keyword.trim()},
    );
    return (response['data'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ScheduledTask.fromJson(_map(item)))
        .toList(growable: false);
  }

  @override
  Future<ScheduledTask> fetchTask(String id) async {
    final response = await _api.getJson('/scheduled-tasks/$id');
    return _taskData(response);
  }

  @override
  Future<ScheduledTask> createTask(ScheduledTaskFormData form) async {
    final response = await _api.postJson('/scheduled-tasks', form.toJson());
    return _taskData(response);
  }

  @override
  Future<ScheduledTask> updateTask(ScheduledTaskFormData form) async {
    final id = form.id;
    if (id == null || id.isEmpty) throw ArgumentError('updateTask requires id');
    final response = await _api.putJson('/scheduled-tasks/$id', form.toJson());
    return _taskData(response);
  }

  @override
  Future<void> deleteTask(String id) async {
    await _api.deleteJson('/scheduled-tasks/$id');
  }

  @override
  Future<ScheduledTaskRun> runTask(String id) async {
    final response = await _api.postJson('/scheduled-tasks/$id/run', const {});
    return ScheduledTaskRun.fromJson(_dataMap(response));
  }

  @override
  Future<ScheduledTaskRunPage> fetchRuns({
    String? taskId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _api.getJson(
      '/scheduled-task-runs',
      queryParameters: {
        if (taskId?.isNotEmpty == true) 'taskId': taskId,
        if (status?.isNotEmpty == true) 'status': status,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return ScheduledTaskRunPage.fromJson(_dataMap(response));
  }

  @override
  Future<ScheduledTaskRun> fetchRun(String id) async {
    final response = await _api.getJson('/scheduled-task-runs/$id');
    return ScheduledTaskRun.fromJson(_dataMap(response));
  }

  @override
  Future<void> stopRun(String id) async {
    await _api.postJson('/scheduled-task-runs/$id/stop', const {});
  }

  @override
  Future<({int batches, int targets})> clearRuns() async {
    final response = await _api.deleteJson('/scheduled-task-runs');
    final data = _dataMap(response);
    return (
      batches: _int(data['batchesRemoved']),
      targets: _int(data['targetsRemoved']),
    );
  }

  ScheduledTask _taskData(Map<String, dynamic> response) {
    return ScheduledTask.fromJson(_dataMap(response));
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) throw ApiFailure('定时任务响应格式异常');
    return _map(data);
  }
}

Map<String, dynamic> _map(Map value) =>
    value.map((key, value) => MapEntry(key.toString(), value));

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
