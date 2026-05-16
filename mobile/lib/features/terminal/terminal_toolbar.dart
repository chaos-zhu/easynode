import 'package:flutter/material.dart';

/// Mobile-only key bar that sits below the xterm view. Provides escape, tab,
/// arrow keys and a disconnect action; all key events are forwarded to the
/// SSH session via [onInput] (not the local xterm buffer).
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.onInput,
    required this.onDisconnect,
  });

  final ValueChanged<String> onInput;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            _ToolbarButton(label: 'Esc', onTap: () => onInput('\x1b')),
            _ToolbarButton(label: 'Tab', onTap: () => onInput('\t')),
            _ToolbarButton(label: '↑', onTap: () => onInput('\x1b[A')),
            _ToolbarButton(label: '↓', onTap: () => onInput('\x1b[B')),
            _ToolbarButton(label: '←', onTap: () => onInput('\x1b[D')),
            _ToolbarButton(label: '→', onTap: () => onInput('\x1b[C')),
            _ToolbarButton(label: 'Ctrl-C', onTap: () => onInput('\x03')),
            _ToolbarButton(label: 'Ctrl-D', onTap: () => onInput('\x04')),
            _ToolbarButton(label: 'Enter', onTap: () => onInput('\r')),
            _ToolbarButton(
              label: '断开',
              onTap: onDisconnect,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: TextButton(
        key: Key('toolbar-$label'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          foregroundColor: color,
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
