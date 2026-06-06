/// Mobile-side projection of `/api/v1/script-group` items.
///
/// The server seeds two special groups: `default` (cannot be deleted, the
/// fallback when others are removed) and `builtin` (read-only, contains the
/// shell-library entries). [isDefault] / [isBuiltin] let the UI gate edits.
class ScriptGroupModel {
  const ScriptGroupModel({
    required this.id,
    required this.name,
    required this.index,
  });

  final String id;
  final String name;
  final int index;

  bool get isDefault => id == 'default';
  bool get isBuiltin => id == 'builtin';
  String get displayName => name.isEmpty ? id : name;

  factory ScriptGroupModel.fromJson(Map<String, dynamic> json) {
    final rawIndex = json['index'];
    final int index;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is num) {
      index = rawIndex.toInt();
    } else {
      index = int.tryParse(rawIndex?.toString() ?? '') ?? 0;
    }
    return ScriptGroupModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      index: index,
    );
  }
}
