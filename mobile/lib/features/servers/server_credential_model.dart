/// Server `ssh.js` returns credential records with secrets stripped:
/// `{ id, name, authType, privateKey:'', password:'', openSSHKeyPassword:'', date }`.
/// For mobile we only display the metadata; secrets are write-only via the
/// add/update flow.
class ServerCredentialModel {
  const ServerCredentialModel({
    required this.id,
    required this.name,
    required this.authType,
    this.date,
  });

  final String id;
  final String name;
  final String authType;
  final int? date;

  factory ServerCredentialModel.fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'];
    int? date;
    if (dateRaw is int) {
      date = dateRaw;
    } else if (dateRaw is num) {
      date = dateRaw.toInt();
    } else if (dateRaw is String) {
      date = int.tryParse(dateRaw);
    }
    return ServerCredentialModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      date: date,
    );
  }

  String get displayName => name.isEmpty ? id : name;
  bool get isPrivateKey => authType == 'privateKey';
}
