import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../features/scripts/script_group_model.dart';
import '../../features/scripts/script_model.dart';
import '../../features/scripts/script_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/script_group_list_notifier.dart';
import '../../state/script_list_notifier.dart';

typedef TerminalScriptSend = bool Function(String command, bool useBase64);

class TerminalScriptLibrarySheet extends ConsumerStatefulWidget {
  const TerminalScriptLibrarySheet({super.key, required this.onSend});

  final TerminalScriptSend onSend;

  @override
  ConsumerState<TerminalScriptLibrarySheet> createState() =>
      _TerminalScriptLibrarySheetState();
}

class _TerminalScriptLibrarySheetState
    extends ConsumerState<TerminalScriptLibrarySheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _selectedGroupId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openEdit(ScriptModel script) async {
    if (script.isBuiltin) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.tr('scripts.builtinReadonly'))));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) =>
          _TerminalScriptEditSheet(script: script, onSend: widget.onSend),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scriptsAsync = ref.watch(scriptListProvider);
    final groups = ref.watch(scriptGroupListProvider).valueOrNull ?? const [];
    final l = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.42,
        maxChildSize: 0.90,
        expand: false,
        builder: (context, scrollController) {
          return _SheetFrame(
            title: l.tr('terminal.menu.scripts'),
            icon: Icons.article_outlined,
            onClose: () => Navigator.of(context).pop(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchCtrl,
                      cursorColor: AppPalette.primary,
                      style: const TextStyle(
                        color: AppPalette.text,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: l.tr('scripts.searchHint'),
                        hintStyle: const TextStyle(color: AppPalette.softMuted),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 19,
                          color: AppPalette.softMuted,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: AppPalette.chip,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppPalette.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppPalette.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppPalette.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                ),
                Expanded(
                  child: scriptsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                      children: [
                        Text(
                          l.trf('scripts.loadFailed', [error.toString()]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              ref.read(scriptListProvider.notifier).refresh();
                              ref
                                  .read(scriptGroupListProvider.notifier)
                                  .refresh();
                            },
                            child: Text(l.tr('common.retry')),
                          ),
                        ),
                      ],
                    ),
                    data: (scripts) => _ScriptListBody(
                      controller: scrollController,
                      scripts: _filteredScripts(scripts),
                      allScripts: scripts,
                      groups: groups,
                      selectedGroupId: _effectiveGroupId(groups),
                      onGroupSelected: (id) =>
                          setState(() => _selectedGroupId = id),
                      onSend: (script) {
                        if (widget.onSend(script.command, script.useBase64)) {
                          Navigator.of(context).pop();
                        }
                      },
                      onEdit: _openEdit,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<ScriptModel> _filteredScripts(List<ScriptModel> scripts) {
    final groupId = _effectiveGroupId(
      ref.read(scriptGroupListProvider).valueOrNull ?? const [],
    );
    return scripts
        .where((script) {
          if (groupId != null && script.group != groupId) return false;
          if (_query.isEmpty) return true;
          final haystack =
              '${script.name} ${script.description} ${script.command}'
                  .toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }

  String? _effectiveGroupId(List<ScriptGroupModel> groups) {
    final selected = _selectedGroupId;
    if (selected == null) return null;
    return groups.any((g) => g.id == selected) ? selected : null;
  }
}

class _ScriptListBody extends StatelessWidget {
  const _ScriptListBody({
    required this.controller,
    required this.scripts,
    required this.allScripts,
    required this.groups,
    required this.selectedGroupId,
    required this.onGroupSelected,
    required this.onSend,
    required this.onEdit,
  });

  final ScrollController controller;
  final List<ScriptModel> scripts;
  final List<ScriptModel> allScripts;
  final List<ScriptGroupModel> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<ScriptModel> onSend;
  final ValueChanged<ScriptModel> onEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (allScripts.isEmpty) {
      return _MessageList(
        controller: controller,
        message: l.tr('scripts.emptyHint'),
      );
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
      children: [
        _ScriptGroupChips(
          groups: groups,
          scripts: allScripts,
          selectedGroupId: selectedGroupId,
          onSelected: onGroupSelected,
        ),
        if (scripts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Text(
              l.tr('scripts.emptyFiltered'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppPalette.softMuted),
            ),
          )
        else
          for (final script in scripts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScriptActionCard(
                script: script,
                groupName: _groupName(script, groups),
                onSend: () => onSend(script),
                onEdit: script.isBuiltin ? null : () => onEdit(script),
              ),
            ),
      ],
    );
  }

  static String _groupName(ScriptModel script, List<ScriptGroupModel> groups) {
    for (final group in groups) {
      if (group.id == script.group) return group.displayName;
    }
    return script.group;
  }
}

class _ScriptGroupChips extends StatelessWidget {
  const _ScriptGroupChips({
    required this.groups,
    required this.scripts,
    required this.selectedGroupId,
    required this.onSelected,
  });

  final List<ScriptGroupModel> groups;
  final List<ScriptModel> scripts;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{for (final group in groups) group.id: 0};
    for (final script in scripts) {
      counts[script.group] = (counts[script.group] ?? 0) + 1;
    }
    final visible = groups
        .where((group) => (counts[group.id] ?? 0) > 0)
        .toList(growable: false);
    if (visible.length < 2) return const SizedBox(height: 4);
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _FilterChipButton(
              label: l.tr('common.all'),
              selected: selectedGroupId == null,
              onTap: () => onSelected(null),
            );
          }
          final group = visible[index - 1];
          return _FilterChipButton(
            label: group.displayName,
            selected: selectedGroupId == group.id,
            onTap: () => onSelected(group.id),
          );
        },
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppPalette.primary,
        backgroundColor: AppPalette.chip,
        labelStyle: TextStyle(
          color: selected ? AppPalette.fontOnPrimary : AppPalette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(
          color: selected ? AppPalette.primary : AppPalette.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        showCheckmark: false,
      ),
    );
  }
}

class _ScriptActionCard extends StatelessWidget {
  const _ScriptActionCard({
    required this.script,
    required this.groupName,
    required this.onSend,
    required this.onEdit,
  });

  final ScriptModel script;
  final String groupName;
  final VoidCallback onSend;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: AppPalette.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSend,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      script.name.isEmpty ? '--' : script.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _EncodingChip(useBase64: script.useBase64),
                ],
              ),
              if (script.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  script.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _CommandPreview(command: script.command),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 14,
                    color: AppPalette.softMuted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppPalette.softMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  _ScriptIconAction(
                    tooltip: l.tr('terminal.script.send'),
                    icon: Icons.send_outlined,
                    primary: true,
                    onPressed: onSend,
                  ),
                  const SizedBox(width: 6),
                  _ScriptIconAction(
                    tooltip: l.tr('scripts.action.edit'),
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptIconAction extends StatelessWidget {
  const _ScriptIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: !enabled
            ? AppPalette.chip
            : primary
            ? AppPalette.primary
            : AppPalette.chip,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: !enabled
                  ? AppPalette.softMuted
                  : primary
                  ? AppPalette.fontOnPrimary
                  : AppPalette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalScriptEditSheet extends ConsumerStatefulWidget {
  const _TerminalScriptEditSheet({required this.script, required this.onSend});

  final ScriptModel script;
  final TerminalScriptSend onSend;

  @override
  ConsumerState<_TerminalScriptEditSheet> createState() =>
      _TerminalScriptEditSheetState();
}

class _TerminalScriptEditSheetState
    extends ConsumerState<_TerminalScriptEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _commandCtrl;
  late bool _useBase64;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.script.name);
    _descriptionCtrl = TextEditingController(text: widget.script.description);
    _commandCtrl = TextEditingController(text: widget.script.command);
    _useBase64 = widget.script.useBase64;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _commandCtrl.dispose();
    super.dispose();
  }

  void _sendOnly() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sent = widget.onSend(_commandCtrl.text, _useBase64);
    if (sent && mounted) Navigator.of(context).pop();
  }

  Future<void> _saveAndSend() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final form = ScriptFormData(
        id: widget.script.id,
        name: _nameCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        command: _commandCtrl.text,
        index: widget.script.index ?? 0,
        group: widget.script.group,
        useBase64: _useBase64,
      );
      final message = await ref
          .read(scriptRepositoryProvider)
          .updateScript(form);
      await ref.read(scriptListProvider.notifier).refresh();
      if (!mounted) return;
      final sent = widget.onSend(form.command, form.useBase64);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (sent) {
        Navigator.of(context).pop();
      } else {
        setState(() => _saving = false);
      }
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.trf('scripts.saveFailed', [error.toString()])),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: _SheetFrame(
            title: l.tr('scripts.editScript'),
            icon: Icons.edit_outlined,
            onClose: () => Navigator.of(context).pop(),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _TextField(
                          controller: _nameCtrl,
                          label: l.tr('scripts.field.name'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? l.tr('scripts.validation.name')
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _TextField(
                          controller: _descriptionCtrl,
                          label: l.tr('scripts.field.description'),
                        ),
                        const SizedBox(height: 12),
                        _TextField(
                          controller: _commandCtrl,
                          label: l.tr('scripts.field.command'),
                          minLines: 8,
                          maxLines: 14,
                          monospace: true,
                          validator: (value) => (value ?? '').isEmpty
                              ? l.tr('scripts.validation.command')
                              : null,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.tr('scripts.useBase64.base64')),
                          subtitle: Text(l.tr('scripts.useBase64.base64Hint')),
                          value: _useBase64,
                          onChanged: (value) =>
                              setState(() => _useBase64 = value),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _sendOnly,
                            icon: const Icon(Icons.send_outlined),
                            label: Text(l.tr('terminal.script.send')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _saveAndSend,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(l.tr('terminal.script.saveAndSend')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.validator,
    this.minLines = 1,
    this.maxLines = 1,
    this.monospace = false,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final int minLines;
  final int maxLines;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(fontFamily: monospace ? 'monospace' : null),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
  });

  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(top: BorderSide(color: AppPalette.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.strongBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, size: 21, color: AppPalette.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).tr('common.close'),
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppPalette.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CommandPreview extends StatelessWidget {
  const _CommandPreview({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final firstLine = command.split('\n').first.trim();
    final text = command.contains('\n') ? '$firstLine ...' : firstLine;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppPalette.chip,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          const Text(
            '\$',
            style: TextStyle(
              color: AppPalette.softMuted,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppPalette.text,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EncodingChip extends StatelessWidget {
  const _EncodingChip({required this.useBase64});

  final bool useBase64;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: useBase64 ? AppPalette.banner : AppPalette.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: useBase64 ? AppPalette.strongBorder : AppPalette.border,
        ),
      ),
      child: Text(
        useBase64
            ? l.tr('scripts.useBase64.base64')
            : l.tr('scripts.useBase64.direct'),
        style: TextStyle(
          color: useBase64 ? AppPalette.primary : AppPalette.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller, required this.message});

  final ScrollController controller;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppPalette.softMuted),
        ),
      ],
    );
  }
}
