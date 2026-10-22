import 'package:flutter/material.dart';

import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import 'terminal_widgets.dart';

Future<String?> terminalTextPrompt(
  BuildContext context, {
  required String title,
  String value = '',
  String? hint,
  String? Function(String)? validate,
}) => showAppDialog<String>(
  context: context,
  builder: (_) => _TerminalTextPrompt(
    title: title,
    value: value,
    hint: hint,
    validate: validate,
  ),
);

class _TerminalTextPrompt extends StatefulWidget {
  const _TerminalTextPrompt({
    required this.title,
    required this.value,
    this.hint,
    this.validate,
  });
  final String title, value;
  final String? hint;
  final String? Function(String)? validate;
  @override
  State<_TerminalTextPrompt> createState() => _TerminalTextPromptState();
}

class _TerminalTextPromptState extends State<_TerminalTextPrompt> {
  late final _controller = TextEditingController(text: widget.value);
  final _form = GlobalKey<FormState>();
  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    title: widget.title,
    width: 460,
    body: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: desktopInputDecoration(context, hint: widget.hint),
        validator: (value) =>
            widget.validate?.call(value!.trim()) ??
            (value!.trim().isEmpty ? dt(context, 'required') : null),
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: Text(dt(context, 'cancel')),
      ),
      FilledButton(onPressed: _submit, child: Text(dt(context, 'confirm'))),
    ],
  );
}
