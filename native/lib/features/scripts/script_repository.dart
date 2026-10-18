import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import 'script_group_model.dart';
import 'script_model.dart';
import '../order/order_layout.dart';

class ScriptCatalog {
  const ScriptCatalog({
    required this.scripts,
    required this.groups,
    required this.order,
  });

  final List<ScriptModel> scripts;
  final List<ScriptGroupModel> groups;
  final OrderLayout order;

  factory ScriptCatalog.fromJson(Map<String, dynamic> json) => ScriptCatalog(
    scripts: (json['scripts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ScriptModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false),
    groups: (json['groups'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ScriptGroupModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false),
    order: OrderLayout.fromJson(
      (json['order'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    ),
  );
}

/// Form payload mirroring web `script-edit.vue`. All fields are required by
/// the backend (`addScript` validates name/command); pass empty strings for
/// optional descriptions, and `useBase64 = false` by default.
class ScriptFormData {
  ScriptFormData({
    this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.group,
    required this.useBase64,
  });

  String? id;
  String name;
  String description;
  String command;
  String group;
  bool useBase64;

  bool get isEdit => id != null && id!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'command': command,
    'group': group,
    'useBase64': useBase64,
  };
}

/// Form payload for the script-group editor.
class ScriptGroupFormData {
  ScriptGroupFormData({this.id, required this.name});

  String? id;
  String name;

  bool get isEdit => id != null && id!.isNotEmpty;

  Map<String, dynamic> toJson() => {'name': name};
}

/// Interface so widget tests can inject a fake repository without touching
/// real HTTP.
abstract class ScriptRepository {
  Future<List<ScriptModel>> fetchScripts();
  Future<List<ScriptGroupModel>> fetchGroups();
  Future<ScriptCatalog> fetchCatalog() async => ScriptCatalog(
    scripts: await fetchScripts(),
    groups: await fetchGroups(),
    order: const OrderLayout(schemaVersion: 1, revision: 0, sections: []),
  );

  /// Waits for reads started before a mutation notice without reusing their data.
  Future<void> settlePendingCatalog() async {}
  Future<OrderLayout> updateOrder(int revision, List<OrderChange> changes) =>
      throw UnsupportedError('Script ordering is not supported');
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
///   GET    /script-catalog    list scripts, groups and layout
///   POST   /script            create
///   PUT    /script/:id        update
///   DELETE /script/:id        delete
///   POST   /batch-remove-script
///   POST   /script-group      create  (Plus only — backend may 403/fail)
///   PUT    /script-group/:id  update  (Plus only)
///   DELETE /script-group/:id  delete  (Plus only)
class ApiScriptRepository implements ScriptRepository {
  ApiScriptRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;
  Future<ScriptCatalog>? _catalogRequest;

  Future<ScriptCatalog> _loadCatalog() {
    final pending = _catalogRequest;
    if (pending != null) return pending;
    final request = _fetchCatalog();
    _catalogRequest = request;
    request.then<void>(
      (_) {
        if (identical(_catalogRequest, request)) _catalogRequest = null;
      },
      onError: (_) {
        if (identical(_catalogRequest, request)) _catalogRequest = null;
      },
    );
    return request;
  }

  Future<ScriptCatalog> _fetchCatalog() async {
    final response = await _api.getJson('/script-catalog');
    final data = response['data'];
    if (data is! Map) {
      return const ScriptCatalog(
        scripts: [],
        groups: [],
        order: OrderLayout(schemaVersion: 1, revision: 0, sections: []),
      );
    }
    return ScriptCatalog.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<List<ScriptModel>> fetchScripts() async {
    return (await _loadCatalog()).scripts;
  }

  @override
  Future<List<ScriptGroupModel>> fetchGroups() async {
    return (await _loadCatalog()).groups;
  }

  @override
  Future<ScriptCatalog> fetchCatalog() => _loadCatalog();

  @override
  Future<void> settlePendingCatalog() async {
    try {
      await _catalogRequest;
    } catch (_) {
      // The next refresh retries; an earlier read failure is not its result.
    }
  }

  @override
  Future<OrderLayout> updateOrder(
    int revision,
    List<OrderChange> changes,
  ) async {
    final response = await _api.putJson('/script-order', {
      'revision': revision,
      'changes': changes.map((change) => change.toJson()).toList(),
    });
    final data = response['data'];
    if (data is! Map) throw ApiFailure('排序响应格式异常');
    return OrderLayout.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
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
