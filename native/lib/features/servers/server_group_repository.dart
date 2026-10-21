import '../../core/api/api_client.dart';

abstract class ServerGroupRepository {
  Future<void> create(String name);
  Future<void> rename(String id, String name);
  Future<void> delete(String id);
}

/// Desktop group management uses the same endpoints as Web.
class ApiServerGroupRepository implements ServerGroupRepository {
  const ApiServerGroupRepository(this._api);
  final ApiClient _api;

  @override
  Future<void> create(String name) async {
    await _api.postJson('/group', {'name': name});
  }

  @override
  Future<void> rename(String id, String name) async {
    await _api.putJson('/group/${Uri.encodeComponent(id)}', {'name': name});
  }

  @override
  Future<void> delete(String id) async {
    await _api.deleteJson('/group/${Uri.encodeComponent(id)}');
  }
}
