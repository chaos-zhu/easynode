import 'package:flutter/material.dart';

class TerminalToolbar extends StatefulWidget {
  const TerminalToolbar({super.key, required this.onInput});

  final ValueChanged<String> onInput;

  @override
  State<TerminalToolbar> createState() => _TerminalToolbarState();
}

class _TerminalToolbarState extends State<TerminalToolbar> {
  bool _ctrlPending = false;

  void _send(String value) {
    if (_ctrlPending && value.length == 1) {
      final code = value.toUpperCase().codeUnitAt(0);
      if (code >= 64 && code <= 95) {
        widget.onInput(String.fromCharCode(code - 64));
        setState(() => _ctrlPending = false);
        return;
      }
    }
    widget.onInput(value);
    if (_ctrlPending) setState(() => _ctrlPending = false);
  }

  void _toggleCtrl() {
    setState(() => _ctrlPending = !_ctrlPending);
  }

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
            _ToolbarButton(label: 'Esc', onTap: () => _send('\x1b')),
            _ToolbarButton(label: 'Tab', onTap: () => _send('\t')),
            _ToolbarButton(
              label: 'Ctrl',
              selected: _ctrlPending,
              onTap: _toggleCtrl,
            ),
            _ToolbarButton(label: 'C', onTap: () => _send('C')),
            _ToolbarButton(label: 'D', onTap: () => _send('D')),
            _ToolbarButton(label: 'Z', onTap: () => _send('Z')),
            _ToolbarButton(label: 'Up', onTap: () => _send('\x1b[A')),
            _ToolbarButton(label: 'Down', onTap: () => _send('\x1b[B')),
            _ToolbarButton(label: 'Left', onTap: () => _send('\x1b[D')),
            _ToolbarButton(label: 'Right', onTap: () => _send('\x1b[C')),
            _ToolbarButton(label: '~', onTap: () => _send('~')),
            _ToolbarButton(label: '/', onTap: () => _send('/')),
            _ToolbarButton(label: '-', onTap: () => _send('-')),
            _ToolbarButton(label: 'L', onTap: () => _send('L')),
            _ToolbarButton(label: 'A', onTap: () => _send('A')),
            _ToolbarButton(label: 'E', onTap: () => _send('E')),
            _ToolbarButton(label: 'PgUp', onTap: () => _send('\x1b[5~')),
            _ToolbarButton(label: 'PgDn', onTap: () => _send('\x1b[6~')),
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
