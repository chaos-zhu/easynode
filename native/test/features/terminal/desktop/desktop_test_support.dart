import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_ssh_connection.dart';
import 'package:easynode_native/features/terminal/server_status_monitor_manager.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';

class FakeConnection implements DesktopTerminalConnection {
  final writes = <String>[];
  late void Function(String) output;
  late void Function(Object?) closed;
  int closes = 0, connects = 0;
  SshConnectionConfig? config;
  @override
  Future<void> connect(
    SshConnectionConfig config, {
    required void Function(String) onData,
    required void Function(Object?) onClosed,
    required int columns,
    required int rows,
  }) async {
    this.config = config;
    output = onData;
    closed = onClosed;
    connects++;
  }

  @override
  void write(String data) => writes.add(data);
  @override
  void resize(int columns, int rows) {}
  @override
  Future<Duration> ping() async => const Duration(milliseconds: 12);
  @override
  Future<void> close() async {
    closes++;
  }
}

class FakeMonitor extends ServerStatusMonitorManager {
  final attached = <String>{};
  @override
  Future<void> attach({
    required String sessionId,
    required SshConnectionConfig config,
  }) async {
    attached.add(sessionId);
  }

  @override
  Future<void> detach({
    required String sessionId,
    required String hostId,
  }) async {
    attached.remove(sessionId);
  }
}

ServerModel host(String id) => ServerModel.fromJson({
  '_id': id,
  'name': id,
  'host': '127.0.0.1',
  'username': 'root',
  'isConfig': true,
});
