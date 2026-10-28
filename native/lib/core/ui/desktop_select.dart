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
    this.optionColors = const {},
    this.placeholder,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.clearable = false,
    this.selectAll = false,
    this.selectAllHint,
    this.showSelectionOrder = true,
    this.controlHeight = desktopFormControlHeight,
    this.allowCreate = false,
    this.maxVisibleTags,
  });

  final Map<String, String> options;
  final List<String> values;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onRemoved;
  final Map<String, String> descriptions;
  final Map<String, Color> optionColors;
  final String? placeholder;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final bool clearable, selectAll, showSelectionOrder;
  final String? selectAllHint;
  final double controlHeight;
  final bool allowCreate;
  final int? maxVisibleTags;

  @override
  State<DesktopSelect> createState() => _DesktopSelectState();
}

class _DesktopSelectState extends State<DesktopSelect> {
  bool _open = false;
  final _focusNode = FocusNode();
  final _query = TextEditingController();

  @override
  void dispose() {
    _focusNode.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _show(BuildContext anchorContext) async {
    if (_open || !widget.enabled) return;
    setState(() => _open = true);
    final selected = [...widget.values];
    final multiple = widget.onRemoved != null;
    final query = _query..clear();
    final result = await showDesktopPopover<String>(
      context: anchorContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setPanelState) {
          final search = query.text.trim();
          final options = widget.options.entries
              .where(
                (option) =>
                    !widget.allowCreate ||
                    option.value.toLowerCase().contains(search.toLowerCase()),
              )
              .toList();
          void create(String value) {
            final text = value.trim();
            if (text.isEmpty) return;
            final id =
                widget.options.entries
                    .where(
                      (option) => option.key == text || option.value == text,
                    )
                    .firstOrNull
                    ?.key ??
                text;
            if (!multiple) {
              Navigator.of(context).pop(id);
              return;
            }
            setPanelState(() {
              if (!selected.contains(id)) {
                selected.add(id);
                widget.onSelected(id);
              }
              query.clear();
            });
          }

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.allowCreate)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      key: const Key('desktop-select-create'),
                      controller: query,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: desktopInputDecoration(
                        context,
                        controlHeight: 36,
                        hint: widget.placeholder,
                      ),
                      onChanged: (_) => setPanelState(() {}),
                      onSubmitted: create,
                    ),
                  ),
                if (multiple && widget.selectAll && widget.options.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.colors.border),
                      ),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      tristate: true,
                      value: selected.length == widget.options.length
                          ? true
                          : selected.isEmpty
                          ? false
                          : null,
                      title: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            MaterialLocalizations.of(
                              context,
                            ).selectAllButtonLabel,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (widget.selectAllHint != null)
                            Text(
                              widget.selectAllHint!,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.muted,
                              ),
                            ),
                        ],
                      ),
                      onChanged: (_) => setPanelState(() {
                        if (selected.length == widget.options.length) {
                          for (final id in selected.toList()) {
                            widget.onRemoved!(id);
                          }
                          selected.clear();
                        } else {
                          for (final id in widget.options.keys) {
                            if (!selected.contains(id)) {
                              selected.add(id);
                              widget.onSelected(id);
                            }
                          }
                        }
                      }),
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const Key('desktop-select-options'),
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 5,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.allowCreate &&
                            search.isNotEmpty &&
                            !widget.options.containsKey(search))
                          _SelectOption(
                            label: search,
                            selected: selected.contains(search),
                            autofocus: false,
                            onPressed: () => create(search),
                          ),
                        if (options.isEmpty &&
                            (!widget.allowCreate || search.isEmpty))
                          Focus(
                            autofocus: !widget.allowCreate,
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
                        for (final option in options)
                          _SelectOption(
                            key: ValueKey(option.key),
                            label: option.value,
                            description: widget.descriptions[option.key],
                            color: widget.optionColors[option.key],
                            selected: selected.contains(option.key),
                            autofocus:
                                !widget.allowCreate && option.key == first,
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
                ),
              ],
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
    final tone = multiple || widget.values.isEmpty
        ? null
        : widget.optionColors[widget.values.first];
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
                style:
                    desktopInputButtonStyle(
                      context,
                      active: _open,
                      invalid: widget.errorText != null,
                    ).copyWith(
                      minimumSize: WidgetStatePropertyAll(
                        Size(0, widget.controlHeight),
                      ),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical:
                              (widget.controlHeight -
                                  (multiple && widget.values.isNotEmpty
                                      ? 24
                                      : 20)) /
                              2,
                        ),
                      ),
                    ),
                child: Row(
                  children: [
                    Expanded(
                      child: multiple && widget.values.isNotEmpty
                          ? Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                for (
                                  var i = 0;
                                  i < widget.values.length &&
                                      (widget.maxVisibleTags == null ||
                                          i < widget.maxVisibleTags!);
                                  i++
                                )
                                  DesktopFormTag(
                                    label:
                                        '${widget.showSelectionOrder ? '${i + 1}. ' : ''}${widget.options[widget.values[i]] ?? widget.values[i]}',
                                    color:
                                        widget.showSelectionOrder ||
                                            widget.allowCreate
                                        ? null
                                        : colors.accent,
                                    onRemove: widget.enabled
                                        ? () => widget.onRemoved!(
                                            widget.values[i],
                                          )
                                        : null,
                                  ),
                                if (widget.maxVisibleTags != null &&
                                    widget.values.length >
                                        widget.maxVisibleTags!)
                                  Tooltip(
                                    message: widget.values
                                        .skip(widget.maxVisibleTags!)
                                        .map((v) => widget.options[v] ?? v)
                                        .join('\n'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.chip,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '+ ${widget.values.length - widget.maxVisibleTags!}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.muted,
                                        ),
                                      ),
                                    ),
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
                                    : tone,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.clearable &&
                        widget.values.any((v) => v.isNotEmpty))
                      IconButton(
                        tooltip: AppLocalizations.of(
                          context,
                        ).tr('desktop.servers.clearSelection'),
                        onPressed: !widget.enabled
                            ? null
                            : () {
                                if (multiple) {
                                  for (final v in widget.values.toList()) {
                                    widget.onRemoved!(v);
                                  }
                                } else {
                                  widget.onSelected('');
                                }
                              },
                        icon: const Icon(Icons.cancel_outlined, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 20,
                          height: 20,
                        ),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
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
    this.color,
  });
  final Color? color;
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
            color ?? (selected ? colors.accent : colors.text),
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
