import 'server_model.dart';

class ServerFormData {
  ServerFormData({
    this.id,
    this.connectType = 'ssh',
    this.group = 'default',
    this.name = '',
    this.host = '',
    this.port = 22,
    this.username = 'root',
    this.authType = 'privateKey',
    this.password = '',
    this.privateKey = '',
    this.credential = '',
    this.index = 0,
    this.expired,
    this.expiredNotify = false,
    this.consoleUrl = '',
    this.tag = const [],
    this.command = '',
    this.proxyType = '',
    this.jumpHosts = const [],
    this.proxyServer = '',
  });

  final String? id;
  String connectType;
  String group;
  String name;
  String host;
  int port;
  String username;
  String authType;
  String password;
  String privateKey;
  String credential;
  int index;
  DateTime? expired;
  bool expiredNotify;
  String consoleUrl;
  List<String> tag;
  String command;
  String proxyType;
  List<String> jumpHosts;
  String proxyServer;

  bool get isEdit => id != null && id!.isNotEmpty;
  bool get isRdp => connectType == 'rdp';
  bool get isSsh => connectType == 'ssh';

  factory ServerFormData.add({required int nextIndex}) {
    return ServerFormData(index: nextIndex);
  }

  factory ServerFormData.edit(ServerModel server) {
    return ServerFormData(
      id: server.id,
      connectType: server.connectType.isEmpty ? 'ssh' : server.connectType,
      group: server.group.isEmpty ? 'default' : server.group,
      name: server.name,
      host: server.host,
      port: server.port,
      username: server.username,
      authType: server.authType.isEmpty ? 'privateKey' : server.authType,
      index: server.index,
      proxyType: server.proxyType,
      jumpHosts: server.jumpHosts,
      proxyServer: server.proxyServer,
      tag: server.tag,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'connectType': connectType,
      'group': group,
      'name': name.trim(),
      'host': host.trim(),
      'port': port,
      'username': username.trim(),
      'authType': isRdp ? 'password' : authType,
      'password': password,
      'privateKey': privateKey,
      'credential': credential,
      'index': index,
      'expired': expired?.millisecondsSinceEpoch,
      'expiredNotify': expiredNotify,
      'consoleUrl': consoleUrl.trim(),
      'tag': tag,
      'command': command,
      'proxyType': proxyType,
      'jumpHosts': jumpHosts,
      'proxyServer': proxyServer,
    };
  }
}
