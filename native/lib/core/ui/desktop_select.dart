import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'app_color_theme.dart';
import 'desktop_form_controls.dart';
import 'desktop_popover.dart';

/// Web-style form select. Supplying [onRemoved] enables ordered multi-selection.
class DesktopSelect extends StatefulWidget {
  const DesktopSelect({
    super.key,
    required this.options,
    required this.values,
    required this.onSelected,
    this.onRemoved,
    this.descriptions = const {},
    this.placeholder,
    this.errorText,
    this.helperText,
    this.enabled = true,
  });

  final Map<String, String> options;
  final List<String> values;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onRemoved;
  final Map<String, String> descriptions;
  final String? placeholder;
  final String? errorText;
  final String? helperText;
  final bool enabled;

  @override
  State<DesktopSelect> createState() => _DesktopSelectState();
}

class _DesktopSelectState extends State<DesktopSelect> {
  bool _open = false;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _show(BuildContext anchorContext) async {
    if (_open || !widget.enabled) return;
    setState(() => _open = true);
    final selected = [...widget.values];
    final multiple = widget.onRemoved != null;
    final result = await showDesktopPopover<String>(
      context: anchorContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setPanelState) {
          final first =
              selected.isNotEmpty && widget.options.containsKey(selected.first)
              ? selected.first
              : widget.options.keys.firstOrNull;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  FocusScope.of(context).nextFocus(),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  FocusScope.of(context).previousFocus(),
            },
            child: SingleChildScrollView(
              key: const Key('desktop-select-options'),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.options.isEmpty)
                    Focus(
                      autofocus: true,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          AppLocalizations.of(
                            context,
                          ).tr('desktop.form.noOptions'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.softMuted,
                          ),
                        ),
                      ),
                    ),
                  for (final option in widget.options.entries)
                    _SelectOption(
                      key: ValueKey(option.key),
                      label: option.value,
                      description: widget.descriptions[option.key],
                      selected: selected.contains(option.key),
                      autofocus: option.key == first,
                      onPressed: () {
                        if (!multiple) {
                          Navigator.of(context).pop(option.key);
                          return;
                        }
                        setPanelState(() {
                          if (selected.contains(option.key)) {
                            selected.remove(option.key);
                            widget.onRemoved!(option.key);
                          } else {
                            selected.add(option.key);
                            widget.onSelected(option.key);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    _focusNode.requestFocus();
    if (result != null) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final multiple = widget.onRemoved != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (anchorContext) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _show(anchorContext),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _show(anchorContext),
            },
            child: Semantics(
              expanded: _open,
              child: TextButton(
                focusNode: _focusNode,
                onPressed: widget.enabled ? () => _show(anchorContext) : null,
                style: desktopInputButtonStyle(
                  context,
                  active: _open,
                  invalid: widget.errorText != null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: multiple && widget.values.isNotEmpty
                          ? Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                for (var i = 0; i < widget.values.length; i++)
                                  DesktopFormTag(
                                    label:
                                        '${i + 1}. ${widget.options[widget.values[i]] ?? widget.values[i]}',
                                    onRemove: widget.enabled
                                        ? () => widget.onRemoved!(
                                            widget.values[i],
                                          )
                                        : null,
                                  ),
                              ],
                            )
                          : Text(
                              widget.values.isNotEmpty
                                  ? widget.options[widget.values.first] ??
                                        widget.placeholder ??
                                        ''
                                  : widget.placeholder ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.values.isEmpty
                                    ? colors.softMuted
                                    : null,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 17,
                        color: colors.softMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null || widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 1),
            child: Text(
              widget.errorText ?? widget.helperText!,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: widget.errorText != null
                    ? colors.danger
                    : colors.softMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectOption extends StatelessWidget {
  const _SelectOption({
    super.key,
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
    this.description,
  });
  final String label;
  final String? description;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      child: TextButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(
            selected ? colors.accent : colors.text,
          ),
          backgroundColor: WidgetStatePropertyAll(
            selected ? colors.accentSoft : Colors.transparent,
          ),
          overlayColor: WidgetStatePropertyAll(colors.chip),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          splashFactory: NoSplash.splashFactory,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (description != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.softMuted),
                ),
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              child: selected ? const Icon(Icons.check, size: 16) : null,
            ),
          ],
        ),
      ),
    );
  }
}
