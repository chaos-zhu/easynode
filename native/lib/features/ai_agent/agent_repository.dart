import '../../core/api/api_client.dart';
import 'agent_models.dart';

class AgentRepository {
  const AgentRepository(this._api);

  final ApiClient _api;

  Future<AgentProviderConfig> getConfig() async {
    final response = await _api.getJson('/ai-config');
    return AgentProviderConfig.fromJson(stringMap(response['data']));
  }

  Future<void> saveProvider(AgentProviderConfig config) async {
    await _api.postJson('/ai-config', config.toProviderJson());
  }

  Future<bool> setNativeAgentEnabled(bool enabled) async {
    final response = await _api.patchJson('/ai-config/preferences', {
      'nativeAgentEnabled': enabled,
    });
    final data = stringMap(response['data']);
    return data['nativeAgentEnabled'] != false;
  }

  Future<List<String>> discoverModels({
    required String apiUrl,
    required String apiKey,
  }) async {
    final response = await _api.postJson('/ai-models', {
      'apiUrl': apiUrl.trim(),
      'apiKey': apiKey.trim(),
    });
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .map((item) => stringMap(item)['id']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> updateHostPolicy(AgentHostPolicy policy) async {
    await _api.putJson('/host-save', {
      'id': policy.hostId,
      'aiPolicy': policy.toJson(),
    });
  }

  Future<List<AgentSessionSummary>> getSessions() async {
    final response = await _api.getJson(
      '/agent-sessions',
      queryParameters: const {'scope': 'ops'},
    );
    return mapList(response['data'])
        .map(AgentSessionSummary.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<AgentSession> getSession(String id) async {
    final response = await _api.getJson('/agent-sessions/$id');
    return AgentSession.fromJson(stringMap(response['data']));
  }

  Future<void> renameSession(String id, String title) async {
    await _api.putJson('/agent-sessions/$id', {'title': title.trim()});
  }

  Future<AgentSession> forkSession(
    String id, {
    required int turnIndex,
    int? messageIndex,
  }) async {
    final response = await _api.postJson('/agent-sessions/$id/fork', {
      'turnIndex': turnIndex,
      'messageIndex': ?messageIndex,
    });
    return AgentSession.fromJson(stringMap(response['data']));
  }

  Future<AgentSession> editMessage(
    String id, {
    required int turnIndex,
    required String content,
  }) async {
    final response = await _api.putJson(
      '/agent-sessions/$id/messages/$turnIndex',
      {'content': content.trim()},
    );
    return AgentSession.fromJson(stringMap(response['data']));
  }

  Future<void> deleteSession(String id) async {
    await _api.deleteJson('/agent-sessions/$id');
  }

  Future<void> clearSessions() async {
    await _api.deleteJson(
      '/agent-sessions',
      queryParameters: const {'scope': 'ops'},
    );
  }
}
