import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';

enum TerminalSessionStatus { connecting, connected, disconnected, error }

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.config,
    required this.displayName,
    required this.controller,
    this.status = TerminalSessionStatus.connecting,
    this.lastError,
  });

  final String id;
  final SshConnectionConfig config;
  final String displayName;
  SshTerminalController controller;
  TerminalSessionStatus status;
  String? lastError;
}
