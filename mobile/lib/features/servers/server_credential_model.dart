class ServerCredentialModel {
  const ServerCredentialModel({
    required this.id,
    required this.name,
    required this.authType,
  });

  final String id;
  final String name;
  final String authType;

  factory ServerCredentialModel.fromJson(Map<String, dynamic> json) {
    return ServerCredentialModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
    );
  }

  String get displayName => name.isEmpty ? id : name;
}
