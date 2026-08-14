import 'package:flutter/material.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import 'agent_feedback.dart';
import 'agent_ui_tokens.dart';

class AgentSelectionOption<T> {
  const AgentSelectionOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon = Icons.circle_outlined,
    this.enabled = true,
    this.searchText = '',
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool enabled;
  final String searchText;
}

Future<T?> showAgentSingleSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required List<AgentSelectionOption<T>> options,
  required T? selected,
  bool searchable = false,
  String? searchHint,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AgentSelectionSheet<T>(
    title: title,
    icon: icon,
    options: options,
    selected: selected == null ? <T>{} : {selected},
    searchable: searchable,
    searchHint: searchHint,
    multiple: false,
  ),
);

Future<void> showAgentMultiSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required List<AgentSelectionOption<T>> options,
  required Set<T> selected,
  bool searchable = false,
  String? searchHint,
  String? customValueHint,
  bool allowBulkSelection = false,
  ValueChanged<Set<T>>? onSelectionChanged,
  Future<List<AgentSelectionOption<T>>> Function()? loadOptions,
  String? loadOptionsLabel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AgentSelectionSheet<T>(
    title: title,
    icon: icon,
    options: options,
    selected: selected,
    searchable: searchable,
    searchHint: searchHint,
    customValueHint: customValueHint,
    allowBulkSelection: allowBulkSelection,
    onSelectionChanged: onSelectionChanged,
    loadOptions: loadOptions,
    loadOptionsLabel: loadOptionsLabel,
    multiple: true,
  ),
);

class AgentSelectionSheetFrame extends StatelessWidget {
  const AgentSelectionSheetFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.canvas,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AgentUiTokens.radiusLarge),
      ),
      border: Border(top: BorderSide(color: context.colors.border)),
    ),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.strongBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.chip,
                  borderRadius: BorderRadius.circular(
                    AgentUiTokens.radiusSmall,
                  ),
                ),
                child: Icon(icon, size: 19, color: context.colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?action,
              IconButton(
                tooltip: AppLocalizations.of(context).tr('common.close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: context.colors.muted),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _AgentSelectionSheet<T> extends StatefulWidget {
  const _AgentSelectionSheet({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.searchable,
    required this.multiple,
    this.searchHint,
    this.customValueHint,
    this.allowBulkSelection = false,
    this.onSelectionChanged,
    this.loadOptions,
    this.loadOptionsLabel,
  });

  final String title;
  final IconData icon;
  final List<AgentSelectionOption<T>> options;
  final Set<T> selected;
  final bool searchable;
  final bool multiple;
  final String? searchHint;
  final String? customValueHint;
  final bool allowBulkSelection;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final Future<List<AgentSelectionOption<T>>> Function()? loadOptions;
  final String? loadOptionsLabel;

  @override
  State<_AgentSelectionSheet<T>> createState() =>
      _AgentSelectionSheetState<T>();
}

class _AgentSelectionSheetState<T> extends State<_AgentSelectionSheet<T>> {
  final _search = TextEditingController();
  late final Set<T> selected = {...widget.selected};
  late final List<AgentSelectionOption<T>> options = [...widget.options];
  String query = '';
  bool loadingOptions = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filtered = options
        .where((option) {
          if (query.isEmpty) return true;
          final text =
              '${option.title} ${option.subtitle ?? ''} '
                      '${option.searchText}'
                  .toLowerCase();
          return text.contains(query);
        })
        .toList(growable: false);
    final height =
        MediaQuery.sizeOf(context).height *
        (widget.searchable || widget.multiple ? 0.78 : 0.64);

    return SizedBox(
      height: height.clamp(360.0, 720.0).toDouble(),
      child: AgentSelectionSheetFrame(
        title: widget.title,
        icon: widget.icon,
        action: _headerActions(),
        child: Column(
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  key: const Key('agent-selection-search'),
                  controller: _search,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  decoration: _searchDecoration(
                    context,
                    widget.searchHint ?? l.tr('common.search'),
                  ),
                  onChanged: (value) =>
                      setState(() => query = value.trim().toLowerCase()),
                ),
              ),
            if (widget.multiple && widget.allowBulkSelection)
              _bulkSelectionBar(context, l, filtered),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        l.tr('agent.selection.empty'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _optionTile(context, filtered[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _headerActions() {
    if (widget.loadOptions == null && widget.customValueHint == null) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.loadOptions != null)
          IconButton(
            key: const Key('agent-selection-load-options'),
            tooltip: widget.loadOptionsLabel,
            onPressed: loadingOptions ? null : _loadOptions,
            icon: loadingOptions
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        if (widget.customValueHint != null)
          IconButton(
            key: const Key('agent-selection-add-custom'),
            tooltip: widget.customValueHint,
            onPressed: _promptCustomValue,
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    );
  }

  Widget _bulkSelectionBar(
    BuildContext context,
    AppLocalizations l,
    List<AgentSelectionOption<T>> filtered,
  ) {
    final selectable = filtered
        .where((option) => option.enabled)
        .map((option) => option.value)
        .toSet();
    final selectedInScope = selectable.where(selected.contains).length;
    final allInScopeSelected =
        selectable.isNotEmpty && selectedInScope == selectable.length;
    final filtering = query.isNotEmpty;
    final actionLabel = filtering
        ? l.tr(
            allInScopeSelected
                ? 'agent.selection.clearFiltered'
                : 'agent.selection.selectFiltered',
          )
        : l.tr(
            allInScopeSelected
                ? 'agent.selection.clearAll'
                : 'agent.selection.selectAll',
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: context.colors.chip,
          borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l.trf('agent.selection.selectedCount', [selected.length]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('agent-selection-toggle-all'),
              onPressed: selectable.isEmpty
                  ? null
                  : () => _toggleBulkSelection(
                      selectable,
                      clear: allInScopeSelected,
                    ),
              icon: Icon(
                allInScopeSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                size: 18,
              ),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleBulkSelection(Set<T> values, {required bool clear}) {
    setState(() {
      if (clear) {
        selected.removeAll(values);
      } else {
        selected.addAll(values);
      }
    });
    widget.onSelectionChanged?.call(Set.unmodifiable(selected));
  }

  Widget _optionTile(BuildContext context, AgentSelectionOption<T> option) {
    final checked = selected.contains(option.value);
    return Material(
      color: checked ? context.colors.chip : context.colors.card,
      borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
        onTap: option.enabled ? () => _select(option.value) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
            border: Border.all(
              color: checked ? context.colors.primary : context.colors.border,
              width: checked ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.canvas,
                  borderRadius: BorderRadius.circular(
                    AgentUiTokens.radiusSmall,
                  ),
                ),
                child: Icon(
                  option.icon,
                  size: 18,
                  color: option.enabled
                      ? context.colors.primary
                      : context.colors.softMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: option.enabled
                            ? context.colors.text
                            : context.colors.softMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (option.subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.multiple
                    ? checked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded
                    : checked
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: checked
                    ? context.colors.primary
                    : context.colors.softMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(T value) {
    if (!widget.multiple) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() {
      if (!selected.add(value)) selected.remove(value);
    });
    widget.onSelectionChanged?.call(Set.unmodifiable(selected));
  }

  Future<void> _promptCustomValue() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgentCustomValueSheet(title: widget.customValueHint!),
    );
    if (value == null || !mounted) return;
    _addCustomValue(value);
  }

  void _addCustomValue(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty || T != String) return;
    final typedValue = value as T;
    setState(() {
      if (!options.any((item) => item.value == typedValue)) {
        options.insert(
          0,
          AgentSelectionOption<T>(
            value: typedValue,
            title: value,
            icon: Icons.tune,
          ),
        );
      }
      selected.add(typedValue);
      query = '';
      _search.clear();
    });
    widget.onSelectionChanged?.call(Set.unmodifiable(selected));
  }

  Future<void> _loadOptions() async {
    setState(() => loadingOptions = true);
    try {
      final loaded = await widget.loadOptions!();
      if (!mounted) return;
      setState(() {
        for (final option in loaded.reversed) {
          if (!options.any((item) => item.value == option.value)) {
            options.insert(0, option);
          }
        }
      });
    } catch (error) {
      if (mounted) showAgentError(context, error);
    } finally {
      if (mounted) setState(() => loadingOptions = false);
    }
  }
}

class _AgentCustomValueSheet extends StatefulWidget {
  const _AgentCustomValueSheet({required this.title});

  final String title;

  @override
  State<_AgentCustomValueSheet> createState() => _AgentCustomValueSheetState();
}

class _AgentCustomValueSheetState extends State<_AgentCustomValueSheet> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: 300,
        child: AgentSelectionSheetFrame(
          title: widget.title,
          icon: Icons.memory_outlined,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.tr('agent.settings.customModelDescription'),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('agent-selection-custom-value'),
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: _searchDecoration(
                    context,
                    widget.title,
                    icon: Icons.memory_outlined,
                  ),
                  onSubmitted: _submit,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l.tr('common.add')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit([String? rawValue]) {
    final value = (rawValue ?? controller.text).trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }
}

InputDecoration _searchDecoration(
  BuildContext context,
  String hint, {
  IconData icon = Icons.search,
}) => InputDecoration(
  hintText: hint,
  prefixIcon: Icon(icon, size: 19),
  isDense: true,
  filled: true,
  fillColor: context.colors.card,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.primary, width: 1.2),
  ),
);
