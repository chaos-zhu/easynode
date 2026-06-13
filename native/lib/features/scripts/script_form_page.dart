import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/script_group_list_notifier.dart';
import '../../state/script_list_notifier.dart';
import 'script_group_model.dart';
import 'script_model.dart';
import 'script_repository.dart';

/// Script editor — full-screen page pushed from the scripts list. Mirrors
/// design node `fbTKb` and feature parity with web `script-edit.vue`:
/// group picker, name/description/index, command body, and Base64 toggle.
class ScriptFormPage extends ConsumerStatefulWidget {
  const ScriptFormPage({
    super.key,
    this.script,
    this.defaultGroup,
    this.defaultCommand,
  });

  /// Provided when editing; null when adding.
  final ScriptModel? script;

  /// Group preselected when creating; ignored when [script] is non-null.
  final String? defaultGroup;

  /// Command preselected when creating (e.g. captured from terminal).
  final String? defaultCommand;

  @override
  ConsumerState<ScriptFormPage> createState() => _ScriptFormPageState();
}

class _ScriptFormPageState extends ConsumerState<ScriptFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _indexCtrl = TextEditingController();
  final _commandCtrl = TextEditingController();

  late ScriptFormData _form;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final scripts = ref.read(scriptListProvider).valueOrNull ?? const [];
    if (widget.script != null) {
      final s = widget.script!;
      _form = ScriptFormData(
        id: s.id,
        name: s.name,
        description: s.description,
        command: s.command,
        index: s.index ?? 0,
        group: s.group,
        useBase64: s.useBase64,
      );
    } else {
      // Web behaviour: next index is max+1 within the target group;
      // never pick `builtin` as the default since the picker forbids it.
      final group =
          (widget.defaultGroup == null ||
              widget.defaultGroup!.isEmpty ||
              widget.defaultGroup == 'builtin')
          ? 'default'
          : widget.defaultGroup!;
      final nextIndex =
          scripts
              .where((s) => s.group == group)
              .fold<int>(0, (m, s) => (s.index ?? 0) > m ? s.index! : m) +
          1;
      _form = ScriptFormData(
        name: '',
        description: '',
        command: widget.defaultCommand ?? '',
        index: nextIndex,
        group: group,
        useBase64: false,
      );
    }
    _syncControllers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _indexCtrl.dispose();
    _commandCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _nameCtrl.text = _form.name;
    _descriptionCtrl.text = _form.description;
    _indexCtrl.text = _form.index.toString();
    _commandCtrl.text = _form.command;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(scriptRepositoryProvider);
    try {
      final form = ScriptFormData(
        id: _form.id,
        name: _nameCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        command: _commandCtrl.text,
        index: int.tryParse(_indexCtrl.text.trim()) ?? 0,
        group: _form.group,
        useBase64: _form.useBase64,
      );
      final message = form.isEdit
          ? await repo.updateScript(form)
          : await repo.createScript(form);
      await ref.read(scriptListProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final groups =
        ref.watch(scriptGroupListProvider).valueOrNull ??
        const <ScriptGroupModel>[];
    final editing = _form.isEdit;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          editing ? l.tr('scripts.editScript') : l.tr('scripts.addScript'),
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: IconThemeData(color: c.text),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AppBarSaveChip(
              loading: _saving,
              onTap: _saving ? null : _save,
              label: l.tr('common.save'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomActionBar(
          saving: _saving,
          editing: editing,
          onCancel: _saving ? null : () => Navigator.of(context).maybePop(),
          onSave: _saving ? null : _save,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SectionCard(
              title: l.tr('scripts.section.basic'),
              children: [
                _LabeledField(
                  label: l.tr('scripts.field.group'),
                  child: _GroupSelector(
                    groups: groups,
                    selected: _form.group,
                    onChanged: (id) => setState(() => _form.group = id),
                  ),
                ),
                _LabeledField(
                  label: l.tr('scripts.field.name'),
                  child: _SoftTextField(
                    controller: _nameCtrl,
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return l.tr('scripts.validation.name');
                      }
                      return null;
                    },
                  ),
                ),
                _LabeledField(
                  label: l.tr('scripts.field.description'),
                  child: _SoftTextField(controller: _descriptionCtrl),
                ),
                _LabeledField(
                  label:
                      '${l.tr('scripts.field.index')}（${l.tr('scripts.field.indexHint')}）',
                  child: SizedBox(
                    width: 140,
                    child: _SoftTextField(
                      controller: _indexCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: l.tr('scripts.section.command'),
              trailing: const _ShellTag(),
              children: [
                _CommandEditor(
                  controller: _commandCtrl,
                  validator: (v) {
                    if ((v ?? '').isEmpty) {
                      return l.tr('scripts.validation.command');
                    }
                    return null;
                  },
                ),
                _LabeledField(
                  label: l.tr('scripts.field.useBase64'),
                  child: Row(
                    children: [
                      Expanded(
                        child: _EncodingOption(
                          title: l.tr('scripts.useBase64.direct'),
                          hint: l.tr('scripts.useBase64.directHint'),
                          selected: !_form.useBase64,
                          onTap: () => setState(() => _form.useBase64 = false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _EncodingOption(
                          title: l.tr('scripts.useBase64.base64'),
                          hint: l.tr('scripts.useBase64.base64Hint'),
                          selected: _form.useBase64,
                          onTap: () => setState(() => _form.useBase64 = true),
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
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: c.softMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SoftTextField extends StatelessWidget {
  const _SoftTextField({
    required this.controller,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      cursorColor: c.primary,
      style: TextStyle(color: c.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.chip,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: c.primary,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: c.danger,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  final List<ScriptGroupModel> groups;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final selectable = groups
        .where((g) => !g.isBuiltin)
        .toList(growable: false);
    final current = groups.firstWhere(
      (g) => g.id == selected,
      orElse: () => ScriptGroupModel(id: selected, name: selected, index: 0),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: selectable.isEmpty
          ? null
          : () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: c.card,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (sheetContext) => SafeArea(
                  top: false,
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (_, i) {
                      final g = selectable[i];
                      final picked = g.id == current.id;
                      return ListTile(
                        title: Text(
                          g.displayName,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: picked
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: picked
                            ? Icon(
                                Icons.check,
                                color: c.primary,
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(g.id),
                      );
                    },
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: c.border),
                    itemCount: selectable.length,
                  ),
                ),
              );
              if (picked != null) onChanged(picked);
            },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current.displayName.isEmpty
                    ? l.tr('scripts.validation.group')
                    : current.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: current.displayName.isEmpty
                      ? c.softMuted
                      : c.text,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: c.softMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellTag extends StatelessWidget {
  const _ShellTag();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.terminal, size: 13, color: c.softMuted),
        const SizedBox(width: 4),
        Text(
          'shell',
          style: TextStyle(
            color: c.softMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CommandEditor extends StatelessWidget {
  const _CommandEditor({required this.controller, required this.validator});

  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        validator: validator,
        maxLines: 8,
        minLines: 6,
        cursorColor: c.primary,
        style: TextStyle(
          color: c.text,
          fontSize: 13,
          fontFamily: 'monospace',
          height: 1.5,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.chip,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: c.primary,
              width: 1.2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.danger),
          ),
        ),
      ),
    );
  }
}

class _EncodingOption extends StatelessWidget {
  const _EncodingOption({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.banner : c.chip,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c.primary : c.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? c.primary
                            : c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: selected
                        ? c.primary
                        : c.softMuted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                style: TextStyle(
                  color: selected
                      ? c.muted
                      : c.softMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBarSaveChip extends StatelessWidget {
  const _AppBarSaveChip({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool loading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.banner,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                )
              else
                Icon(
                  Icons.check,
                  size: 16,
                  color: c.primary,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: c.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.saving,
    required this.editing,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final bool editing;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: c.strongBorder),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onCancel,
              child: SizedBox(
                width: 110,
                height: 48,
                child: Center(
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: onSave == null
                  ? c.softMuted
                  : c.primary,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSave,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.fontOnPrimary,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check,
                                size: 18,
                                color: c.fontOnPrimary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                editing
                                    ? l.tr('common.save')
                                    : l.tr('scripts.addScript'),
                                style: TextStyle(
                                  color: c.fontOnPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
