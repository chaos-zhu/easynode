import 'package:flutter/material.dart';

import 'ssh_terminal_controller.dart';

class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.onInput,
    required this.controller,
  });

  final ValueChanged<String> onInput;
  final SshTerminalController? controller;

  @override
  Widget build(BuildContext context) {
    final ctrlNotifier = controller?.ctrlPending;
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
            ctrlNotifier == null
                ? const _ToolbarButton(label: 'Ctrl', onTap: _noop)
                : ValueListenableBuilder<bool>(
                    valueListenable: ctrlNotifier,
                    builder: (_, pending, _) => _ToolbarButton(
                      label: 'Ctrl',
                      selected: pending,
                      onTap: controller!.toggleCtrl,
                    ),
                  ),
            _ToolbarButton(label: 'Up', onTap: () => onInput('\x1b[A')),
            _ToolbarButton(label: 'Down', onTap: () => onInput('\x1b[B')),
            _ToolbarButton(label: 'Left', onTap: () => onInput('\x1b[D')),
            _ToolbarButton(label: 'Right', onTap: () => onInput('\x1b[C')),
            _ToolbarButton(label: 'PgUp', onTap: () => onInput('\x1b[5~')),
            _ToolbarButton(label: 'PgDn', onTap: () => onInput('\x1b[6~')),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: TextButton(
        key: Key('toolbar-$label'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          backgroundColor: selected ? colors.primaryContainer : null,
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
