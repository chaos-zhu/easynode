class ServerProxyModel {
  const ServerProxyModel({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final String type;

  factory ServerProxyModel.fromJson(Map<String, dynamic> json) {
    return ServerProxyModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }

  String get displayName => name.isEmpty ? id : name;
  String get typeLabel => type.isEmpty ? 'SOCKS' : type.toUpperCase();
}
