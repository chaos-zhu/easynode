import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import 'server_list_config.dart';

abstract class ServerListConfigRepository {
  Future<ServerListConfig> fetch();
  Future<void> save(ServerListConfig config);
}

class ApiServerListConfigRepository implements ServerListConfigRepository {
  const ApiServerListConfigRepository(this._api);

  final ApiClient _api;

  @override
  Future<ServerListConfig> fetch() async {
    final response = await _api.getJson('/server-list-config');
    final data = response['data'];
    if (data is! Map) throw ApiFailure('Invalid server list configuration');
    return ServerListConfig.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<void> save(ServerListConfig config) async {
    // Send only list settings; preserve other server configuration fields.
    await _api.postJson('/server-list-config', config.toJson());
  }
}
