part of 'desktop_terminal_settings_dialog.dart';

class _ThemeEditor extends StatefulWidget {
  const _ThemeEditor({required this.theme});
  final Map<String, dynamic> theme;
  @override
  State<_ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<_ThemeEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.theme['name'] as String,
  );
  late final _colors = {
    for (final key in [
      'foreground',
      'background',
      'cursor',
      'cursorAccent',
      'selectionBackground',
      'selectionForeground',
      'selectionInactiveBackground',
      ...TerminalOutputHighlighter.tokens,
    ])
      key: TextEditingController(
        text: terminalMap(widget.theme['colors'])[key]?.toString() ?? '',
      ),
  };
  @override
  void dispose() {
    _name.dispose();
    for (final c in _colors.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'id': widget.theme['id'],
      'name': _name.text.trim(),
      'colors': {
        for (final entry in _colors.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
    });
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    title: dt(context, 'editTheme'),
    width: 750,
    body: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            maxLength: 40,
            autofocus: true,
            decoration: desktopInputDecoration(
              context,
              hint: dt(context, 'themeName'),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? dt(context, 'required') : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final entry in _colors.entries)
                SizedBox(
                  width: 218,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          ValueListenableBuilder(
                            valueListenable: entry.value,
                            builder: (_, value, _) => Container(
                              width: 12,
                              height: 12,
                              color: terminalColor(
                                value.text,
                                Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      TextFormField(
                        controller: entry.value,
                        decoration: desktopInputDecoration(
                          context,
                          hint: '#RRGGBB',
                        ),
                        validator: (v) =>
                            v != null && v.isNotEmpty && !_validColor(v.trim())
                            ? dt(context, 'invalidColor')
                            : null,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: Text(dt(context, 'cancel')),
      ),
      FilledButton(onPressed: _save, child: Text(dt(context, 'save'))),
    ],
  );
}
