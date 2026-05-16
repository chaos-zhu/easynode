import 'package:flutter/material.dart';

import 'ssh_connection_config.dart';

/// Placeholder terminal page. The full xterm + dartssh2 implementation lands
/// in Task 12; this stub exists so the navigation wiring in Task 10/11 can
/// reference a real widget and the analyzer stays green between commits.
class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key, required this.config});

  final SshConnectionConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(config.name.isEmpty ? config.host : config.name),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '终端尚未实现\n${config.username}@${config.host}:${config.port}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
