import 'package:flutter/material.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';

class DesktopSettingRow extends StatelessWidget {
  const DesktopSettingRow({
    super.key,
    required this.label,
    required this.child,
    this.wide = false,
    this.labelWidth = 106,
    this.maxWidth,
    this.labelAlign = TextAlign.left,
    this.labelTopPadding = 12,
  });
  final String label;
  final Widget child;
  final bool wide;
  final double labelWidth;
  final double? maxWidth;
  final TextAlign labelAlign;
  final double labelTopPadding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: EdgeInsets.only(top: labelTopPadding, right: 14),
            child: Text(
              label,
              textAlign: labelAlign,
              style: TextStyle(fontSize: 13, color: context.colors.text),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? (wide ? 800 : 450),
              ),
              child: child,
            ),
          ),
        ),
      ],
    ),
  );
}

class DesktopSettingInput extends StatefulWidget {
  const DesktopSettingInput({
    super.key,
    required this.controller,
    this.secret = false,
    this.hint,
    this.validator,
    this.lines = 1,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.controlHeight = desktopFormControlHeight,
  });
  final TextEditingController controller;
  final bool secret, enabled;
  final String? hint;
  final String? Function(String?)? validator;
  final int lines;
  final double controlHeight;
  final ValueChanged<String>? onSubmitted, onChanged;
  @override
  State<DesktopSettingInput> createState() => _DesktopSettingInputState();
}

class _DesktopSettingInputState extends State<DesktopSettingInput> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: widget.secret && !_visible,
    maxLines: widget.lines,
    autocorrect: false,
    enableSuggestions: false,
    style: TextStyle(
      fontSize: 13,
      fontFamily: widget.lines > 1 ? 'monospace' : null,
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
    onChanged: widget.onChanged,
    decoration:
        desktopInputDecoration(
          context,
          hint: widget.hint,
          controlHeight: widget.controlHeight,
        ).copyWith(
          suffixIconConstraints: BoxConstraints(
            minWidth: 36,
            minHeight: widget.controlHeight,
          ),
          suffixIcon: widget.secret
              ? IconButton(
                  tooltip: _visible
                      ? mx(context, '隐藏密码', 'Hide password')
                      : mx(context, '显示密码', 'Show password'),
                  constraints: BoxConstraints.tightFor(
                    width: 36,
                    height: widget.controlHeight,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 17,
                  ),
                )
              : null,
        ),
  );
}

class DesktopSettingNumber extends StatelessWidget {
  const DesktopSettingNumber({
    super.key,
    required this.controller,
    required this.min,
    required this.max,
    this.step = 1,
    this.validator,
  });
  final TextEditingController controller;
  final int min, max, step;
  final String? Function(String?)? validator;

  void _adjust(int direction) {
    final value = int.tryParse(controller.text) ?? min;
    controller.text = '${(value + step * direction).clamp(min, max)}';
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    textAlign: TextAlign.center,
    keyboardType: TextInputType.number,
    style: const TextStyle(fontSize: 13),
    validator: validator,
    decoration: desktopInputDecoration(context, controlHeight: 36).copyWith(
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: 32,
        height: 36,
      ),
      suffixIcon: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: context.colors.border)),
        ),
        child: Column(
          children: [
            for (final direction in [1, -1])
              Expanded(
                child: IconButton(
                  tooltip: direction == 1
                      ? mx(context, '增加', 'Increase')
                      : mx(context, '减少', 'Decrease'),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    direction == 1
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                  ),
                  onPressed: () => _adjust(direction),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
