import 'package:flutter/material.dart';

import 'app_color_theme.dart';

const desktopFormControlHeight = 44.0;

/// Compact controls matching the Web management forms. Desktop use only.
InputDecoration desktopInputDecoration(
  BuildContext context, {
  String? hint,
  String? helper,
  String? error,
  double controlHeight = desktopFormControlHeight,
}) {
  final colors = context.colors;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: colors.softMuted, fontSize: 13),
    helperText: helper,
    helperStyle: TextStyle(color: colors.softMuted, fontSize: 12),
    helperMaxLines: 3,
    errorText: error,
    errorMaxLines: 3,
    errorStyle: TextStyle(color: colors.danger, fontSize: 12),
    isDense: true,
    constraints: BoxConstraints(minHeight: controlHeight),
    filled: true,
    fillColor: colors.card,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: (controlHeight - 20) / 2,
    ),
    border: border(colors.border),
    enabledBorder: border(colors.border),
    disabledBorder: border(colors.border),
    focusedBorder: border(colors.accent),
    errorBorder: border(colors.danger),
    focusedErrorBorder: border(colors.danger),
  );
}

ButtonStyle desktopButtonStyle(BuildContext context, {bool primary = false}) {
  final colors = context.colors;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(76, 36)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.softMuted
          : primary
          ? colors.fontOnPrimary
          : colors.text,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.chip
          : primary
          ? colors.accent
          : colors.card,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: primary
            ? Colors.transparent
            : states.contains(WidgetState.hovered)
            ? colors.accent
            : colors.border,
      ),
    ),
    overlayColor: WidgetStatePropertyAll(
      primary ? colors.fontOnPrimary.withValues(alpha: .12) : colors.accentSoft,
    ),
    splashFactory: NoSplash.splashFactory,
  );
}

ButtonStyle desktopInputButtonStyle(
  BuildContext context, {
  bool active = false,
  bool invalid = false,
}) {
  final colors = context.colors;
  return ButtonStyle(
    alignment: Alignment.centerLeft,
    minimumSize: const WidgetStatePropertyAll(
      Size(0, desktopFormControlHeight),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.softMuted
          : colors.text,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? colors.chip : colors.card,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: invalid
            ? colors.danger
            : active || states.contains(WidgetState.focused)
            ? colors.accent
            : states.contains(WidgetState.hovered)
            ? colors.strongBorder
            : colors.border,
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    splashFactory: NoSplash.splashFactory,
  );
}

class DesktopFormTag extends StatelessWidget {
  const DesktopFormTag({
    super.key,
    required this.label,
    required this.onRemove,
    this.color,
  });

  final String label;
  final VoidCallback? onRemove;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.muted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(7, 3, 4, 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .08),
        border: Border.all(color: tone.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.3, color: tone),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 13),
            color: tone,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 16, height: 16),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
