import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';
import 'terminal_toolbar.dart';

/// SSH terminal screen. Connects on mount, displays the xterm view, and
/// disconnects in [State.dispose] so leaving the page tears down the SSH
/// session.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.config});

  final SshConnectionConfig config;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final SshTerminalController _controller;
  String? _connectError;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _controller = SshTerminalController(config: widget.config);
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _controller.connect();
    } catch (error) {
      if (!mounted) return;
      setState(() => _connectError = error.toString());
      return;
    }
    if (!mounted) return;
    setState(() => _connecting = false);
  }

  @override
  void dispose() {
    _controller.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.config.name.isEmpty
        ? '${widget.config.username}@${widget.config.host}'
        : widget.config.name;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            TerminalToolbar(
              controller: _controller,
              onInput: _controller.writeInput,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_connectError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '连接失败: $_connectError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    return TerminalView(_controller.terminal);
  }
}
