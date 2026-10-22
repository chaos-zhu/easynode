part of 'desktop_terminal_settings_dialog.dart';

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.rule});
  final Map<String, dynamic> rule;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final _rule = cloneTerminalJson(widget.rule);
  late final _title = TextEditingController(text: _rule['title'] as String);
  late final _pattern = TextEditingController(text: _rule['pattern'] as String);
  late final _flags = TextEditingController(text: _rule['flags'] as String);
  late final _priority = TextEditingController(text: '${_rule['priority']}');
  late final _fixedForeground = TextEditingController(
    text: terminalMap(_rule['style']['foreground'])['value']?.toString(),
  );
  late final _fixedBackground = TextEditingController(
    text: terminalMap(_rule['style']['background'])['value']?.toString(),
  );
  Map<String, dynamic> get _style => _rule['style'] as Map<String, dynamic>;
  @override
  void dispose() {
    for (final c in [
      _title,
      _pattern,
      _flags,
      _priority,
      _fixedForeground,
      _fixedBackground,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _rule['title'] = _title.text.trim();
    _rule['pattern'] = _pattern.text;
    _rule['flags'] = _flags.text;
    _rule['priority'] = (int.tryParse(_priority.text) ?? 0).clamp(-1000, 1000);
    Navigator.pop(context, _rule);
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    title: dt(context, 'editRule'),
    width: 720,
    body: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _title,
            maxLength: 60,
            autofocus: true,
            decoration: desktopInputDecoration(
              context,
              hint: dt(context, 'ruleName'),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? dt(context, 'required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pattern,
            maxLines: 3,
            maxLength: 4096,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: desktopInputDecoration(
              context,
              hint: dt(context, 'regexPattern'),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return dt(context, 'required');
              try {
                RegExp(v, unicode: _flags.text.contains('u'));
              } on FormatException {
                return dt(context, 'invalidRegex');
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _flags,
                  decoration: desktopInputDecoration(
                    context,
                    hint: dt(context, 'regexFlags'),
                  ),
                  validator: (v) =>
                      v == null ||
                          !RegExp(r'^(?!.*(.).*\1)[gimu]*$').hasMatch(v)
                      ? dt(context, 'invalidFlags')
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  decoration: desktopInputDecoration(
                    context,
                    hint: dt(context, 'priority'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DesktopSelect(
            options: {
              'match': dt(context, 'match'),
              'line': dt(context, 'line'),
              'lineTail': dt(context, 'lineTail'),
            },
            values: [_rule['scope'] as String],
            onSelected: (v) => setState(() => _rule['scope'] = v),
          ),
          const SizedBox(height: 14),
          _color('foreground', _fixedForeground),
          const SizedBox(height: 14),
          _color('background', _fixedBackground),
          const SizedBox(height: 10),
          Wrap(
            children: [
              for (final key in ['bold', 'italic', 'underline'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _style[key] == true,
                      onChanged: (v) => setState(() => _style[key] = v),
                    ),
                    Text(dt(context, key)),
                  ],
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
  Widget _color(String key, TextEditingController controller) {
    final raw = terminalMap(_style[key]);
    final source = raw.isEmpty ? 'none' : raw['source'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dt(context, key), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: DesktopSelect(
                options: {
                  'none': dt(context, 'inherit'),
                  'theme': dt(context, 'themeColor'),
                  'fixed': dt(context, 'fixedColor'),
                },
                values: [source],
                onSelected: (v) => setState(() {
                  if (v == 'fixed' && controller.text.isEmpty) {
                    controller.text = '#ffffff';
                  }
                  _style[key] = v == 'none'
                      ? null
                      : v == 'theme'
                      ? {'source': 'theme', 'token': 'cyan'}
                      : {
                          'source': 'fixed',
                          'value': controller.text.isEmpty
                              ? '#ffffff'
                              : controller.text,
                        };
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: source == 'theme'
                  ? DesktopSelect(
                      options: {
                        for (final token in TerminalOutputHighlighter.tokens)
                          token: token,
                      },
                      values: [raw['token'] as String],
                      onSelected: (v) => setState(
                        () => _style[key] = {'source': 'theme', 'token': v},
                      ),
                    )
                  : source == 'fixed'
                  ? TextFormField(
                      controller: controller,
                      decoration: desktopInputDecoration(
                        context,
                        hint: '#RRGGBB',
                      ),
                      validator: (v) => v == null || !_validColor(v)
                          ? dt(context, 'invalidColor')
                          : null,
                      onChanged: (v) =>
                          _style[key] = {'source': 'fixed', 'value': v},
                    )
                  : const SizedBox(height: 44),
            ),
          ],
        ),
      ],
    );
  }
}
