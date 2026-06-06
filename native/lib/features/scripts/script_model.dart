/// Mobile-side projection of `/api/v1/script` items.
///
/// Mirrors the schema served by `server/app/controller/scripts.js`. The web
/// shows a few special rows from `local-script` (the built-in shell library)
/// that arrive with `index: '--'` and `group: 'builtin'`; we expose
/// [isBuiltin] for the UI to disable editing on those rows.
class ScriptModel {
  const ScriptModel({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.index,
    required this.group,
    required this.useBase64,
  });

  final String id;
  final String name;
  final String description;
  final String command;

  /// Display order within a group. Built-in scripts carry `'--'` from the
  /// server and surface here as `null` so the UI can render a dash.
  final int? index;
  final String group;
  final bool useBase64;

  bool get isBuiltin => group == 'builtin';

  ScriptModel copyWith({
    String? id,
    String? name,
    String? description,
    String? command,
    int? index,
    String? group,
    bool? useBase64,
  }) {
    return ScriptModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      command: command ?? this.command,
      index: index ?? this.index,
      group: group ?? this.group,
      useBase64: useBase64 ?? this.useBase64,
    );
  }

  factory ScriptModel.fromJson(Map<String, dynamic> json) {
    return ScriptModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      command: (json['command'] ?? '').toString(),
      index: _parseIndex(json['index']),
      group: (json['group'] ?? 'default').toString(),
      useBase64: json['useBase64'] == true,
    );
  }

  static int? _parseIndex(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == '--' || trimmed == '-') return null;
      return int.tryParse(trimmed);
    }
    return null;
  }
}
