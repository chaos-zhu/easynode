class DockerContainer {
  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.ports,
    required this.createdAt,
    required this.uptime,
  });

  final String id;
  final String name;
  final String image;
  final String status;
  final List<String> ports;
  final String createdAt;
  final String uptime;

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    final rawPorts = json['ports'];
    return DockerContainer(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      ports: rawPorts is List
          ? rawPorts.map((port) => port.toString()).toList(growable: false)
          : const [],
      createdAt: (json['createdAt'] ?? '').toString(),
      uptime: (json['uptime'] ?? '').toString(),
    );
  }

  String get shortId => id.length <= 12 ? id : id.substring(0, 12);
  bool get isRunning => status == 'running';
}

class DockerOperationResult {
  const DockerOperationResult({required this.success, required this.message});

  final bool success;
  final String message;

  factory DockerOperationResult.fromJson(dynamic json) {
    if (json is Map) {
      return DockerOperationResult(
        success: json['success'] == true,
        message: (json['message'] ?? '').toString(),
      );
    }
    return const DockerOperationResult(
      success: false,
      message: 'Unknown error',
    );
  }
}
