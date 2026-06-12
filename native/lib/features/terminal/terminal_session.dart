import 'package:flutter/widgets.dart';
import 'package:xterm/ui.dart';

import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';

enum TerminalSessionStatus { connecting, connected, disconnected, error }

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.config,
    required this.displayName,
    required this.controller,
    required this.viewController,
    required this.scrollController,
    required this.viewKey,
    this.status = TerminalSessionStatus.connecting,
    this.lastError,
  });

  final String id;
  final SshConnectionConfig config;
  final String displayName;
  SshTerminalController controller;
  final TerminalController viewController;
  final ScrollController scrollController;
  final GlobalKey<TerminalViewState> viewKey;
  TerminalSessionStatus status;
  String? lastError;
}
