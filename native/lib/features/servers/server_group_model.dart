/// Mobile-side projection of `/api/v1/group` items.
class ServerGroupModel {
  const ServerGroupModel({
    required this.id,
    required this.name,
    required this.index,
  });

  final String id;
  final String name;
  final int index;

  factory ServerGroupModel.fromJson(Map<String, dynamic> json) {
    final rawIndex = json['index'];
    final int index;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is num) {
      index = rawIndex.toInt();
    } else {
      index = int.tryParse(rawIndex?.toString() ?? '') ?? 0;
    }

    return ServerGroupModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      index: index,
    );
  }

  bool get isDefault => id == 'default';
  String get displayName => name.isEmpty ? id : name;
}
