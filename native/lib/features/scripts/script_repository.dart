import '../../core/api/api_client.dart';
import 'script_group_model.dart';
import 'script_model.dart';

/// Form payload mirroring web `script-edit.vue`. All fields are required by
/// the backend (`addScript` validates name/command); pass empty strings for
/// optional descriptions, and `useBase64 = false` by default.
class ScriptFormData {
  ScriptFormData({
    this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.index,
    required this.group,
    required this.useBase64,
  });

  String? id;
  String name;
  String description;
  String command;
  int index;
  String group;
  bool useBase64;

  bool get isEdit => id != null && id!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'command': command,
    'index': index,
    'group': group,
    'useBase64': useBase64,
  };
}

/// Form payload for the script-group editor.
class ScriptGroupFormData {
  ScriptGroupFormData({this.id, required this.name, required this.index});

  String? id;
  String name;
  int index;

  bool get isEdit => id != null && id!.isNotEmpty;

  Map<String, dynamic> toJson() => {'name': name, 'index': index};
}

/// Interface so widget tests can inject a fake repository without touching
/// real HTTP.
abstract class ScriptRepository {
  Future<List<ScriptModel>> fetchScripts();
  Future<List<ScriptGroupModel>> fetchGroups();
  Future<String> createScript(ScriptFormData form);
  Future<String> updateScript(ScriptFormData form);
  Future<String> deleteScript(String id);
  Future<String> batchDeleteScripts(List<String> ids);
  Future<String> createGroup(ScriptGroupFormData form);
  Future<String> updateGroup(ScriptGroupFormData form);
  Future<String> deleteGroup(String id);
}

/// Default [ScriptRepository] backed by [ApiClient]. Endpoints mirror
/// `web/src/api/index.js`:
///   GET    /script            list scripts
///   POST   /script            create
///   PUT    /script/:id        update
///   DELETE /script/:id        delete
///   POST   /batch-remove-script
///   GET    /script-group      list groups
///   POST   /script-group      create  (Plus only — backend may 403/fail)
///   PUT    /script-group/:id  update  (Plus only)
///   DELETE /script-group/:id  delete  (Plus only)
class ApiScriptRepository implements ScriptRepository {
  ApiScriptRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<List<ScriptModel>> fetchScripts() async {
    final response = await _api.getJson('/script');
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ScriptModel.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<ScriptGroupModel>> fetchGroups() async {
    final response = await _api.getJson('/script-group');
    final raw = response['data'];
    if (raw is! List) return const [];
    final groups = raw
        .whereType<Map<String, dynamic>>()
        .map(ScriptGroupModel.fromJson)
        .toList(growable: false);
    return groups;
  }

  @override
  Future<String> createScript(ScriptFormData form) async {
    final response = await _api.postJson('/script', form.toJson());
    return _msg(response);
  }

  @override
  Future<String> updateScript(ScriptFormData form) async {
    final id = form.id;
    if (id == null || id.isEmpty) {
      throw ArgumentError('updateScript requires id');
    }
    final response = await _api.putJson('/script/$id', form.toJson());
    return _msg(response);
  }

  @override
  Future<String> deleteScript(String id) async {
    final response = await _api.deleteJson('/script/$id');
    return _msg(response);
  }

  @override
  Future<String> batchDeleteScripts(List<String> ids) async {
    final response = await _api.postJson('/batch-remove-script', {'ids': ids});
    return _msg(response);
  }

  @override
  Future<String> createGroup(ScriptGroupFormData form) async {
    final response = await _api.postJson('/script-group', form.toJson());
    return _msg(response);
  }

  @override
  Future<String> updateGroup(ScriptGroupFormData form) async {
    final id = form.id;
    if (id == null || id.isEmpty) {
      throw ArgumentError('updateGroup requires id');
    }
    final response = await _api.putJson('/script-group/$id', form.toJson());
    return _msg(response);
  }

  @override
  Future<String> deleteGroup(String id) async {
    final response = await _api.deleteJson('/script-group/$id');
    return _msg(response);
  }

  String _msg(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is String && data.isNotEmpty) return data;
    final msg = response['msg'];
    if (msg is String && msg.isNotEmpty) return msg;
    return 'success';
  }
}
