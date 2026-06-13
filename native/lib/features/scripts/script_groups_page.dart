import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/script_group_list_notifier.dart';
import '../../state/script_list_notifier.dart';
import 'script_group_model.dart';
import 'script_model.dart';
import 'script_repository.dart';

import '../../core/ui/app_color_theme.dart';

/// Group manager — full-screen page pushed from the scripts list AppBar.
/// Mirrors design node `Poem6` and feature parity with web `script-group.vue`:
/// list groups with script-count, add/edit via bottom sheet, delete with
/// confirmation. The `default` group cannot be deleted; the `builtin` group
/// is read-only (server-seeded; backed by `local-script`).
class ScriptGroupsPage extends ConsumerStatefulWidget {
  const ScriptGroupsPage({super.key});

  @override
  ConsumerState<ScriptGroupsPage> createState() => _ScriptGroupsPageState();
}

class _ScriptGroupsPageState extends ConsumerState<ScriptGroupsPage> {
  bool _busy = false;

  bool _ensurePlusOrWarn() {
    if (ref.read(isPlusActiveProvider)) return true;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.tr('scripts.groupsPlusTip'))),
    );
    return false;
  }

  Future<void> _openForm({ScriptGroupModel? group}) async {
    if (!_ensurePlusOrWarn()) return;
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final groups =
        ref.read(scriptGroupListProvider).valueOrNull ??
        const <ScriptGroupModel>[];
    final nextIndex =
        group?.index ??
        (groups.fold<int>(0, (m, g) => g.index > m ? g.index : m) + 1);
    final form = ScriptGroupFormData(
      id: group?.id,
      name: group?.name ?? '',
      index: nextIndex,
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: _GroupForm(form: form),
        );
      },
    );
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            form.isEdit ? l.tr('scripts.editGroup') : l.tr('scripts.addGroup'),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(ScriptGroupModel group) async {
    if (!_ensurePlusOrWarn()) return;
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('scripts.deleteGroupTitle')),
        content: Text(l.trf('scripts.deleteGroupBody', [group.displayName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final message = await ref
          .read(scriptRepositoryProvider)
          .deleteGroup(group.id);
      await Future.wait([
        ref.read(scriptGroupListProvider.notifier).refresh(),
        ref.read(scriptListProvider.notifier).refresh(),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.trf('scripts.deleteFailed', [error.toString()])),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final groupsAsync = ref.watch(scriptGroupListProvider);
    final scripts =
        ref.watch(scriptListProvider).valueOrNull ?? const <ScriptModel>[];
    final isPlus = ref.watch(isPlusActiveProvider);
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l.tr('scripts.groupsTitle'),
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: c.text),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AddChip(
              label: l.tr('scripts.addGroup'),
              onTap: _busy ? null : () => _openForm(),
            ),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is UnauthorizedFailure) {
            return const SizedBox.shrink();
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          );
        },
        data: (groups) {
          final counts = <String, int>{for (final g in groups) g.id: 0};
          for (final s in scripts) {
            counts[s.group] = (counts[s.group] ?? 0) + 1;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (!isPlus) ...[
                _PlusBanner(message: l.tr('scripts.groupsPlusTip')),
                const SizedBox(height: 10),
              ],
              _HintCard(body: l.tr('scripts.groupsHintBody')),
              const SizedBox(height: 12),
              for (var i = 0; i < groups.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _GroupCard(
                    group: groups[i],
                    scriptCount: counts[groups[i].id] ?? 0,
                    onEdit: groups[i].isBuiltin
                        ? null
                        : () => _openForm(group: groups[i]),
                    onDelete:
                        (groups[i].isBuiltin || groups[i].isDefault || _busy)
                        ? null
                        : () => _confirmDelete(groups[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.banner,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: c.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              body,
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusBanner extends StatelessWidget {
  const _PlusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.banner,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.strongBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.workspace_premium_outlined,
              size: 16,
              color: c.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: c.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.scriptCount,
    required this.onEdit,
    required this.onDelete,
  });

  final ScriptGroupModel group;
  final int scriptCount;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (group.isBuiltin) ...[
                      const SizedBox(width: 6),
                      _RoleChip(label: l.tr('scripts.builtinChip')),
                    ] else if (group.isDefault) ...[
                      const SizedBox(width: 6),
                      _RoleChip(label: l.tr('scripts.defaultChip')),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 13,
                      color: c.softMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.trf('scripts.scriptCount', [scriptCount]),
                      style: TextStyle(
                        color: c.softMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (group.isBuiltin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '--',
                style: TextStyle(
                  color: c.softMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Row(
              children: [
                _ActionIcon(
                  icon: Icons.edit_outlined,
                  color: c.muted,
                  onTap: onEdit,
                ),
                _ActionIcon(
                  icon: Icons.delete_outline,
                  color: onDelete == null
                      ? c.softMuted
                      : c.danger,
                  onTap: onDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});
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
              Icon(Icons.add, size: 16, color: c.primary),
              const SizedBox(width: 4),
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

class _GroupForm extends ConsumerStatefulWidget {
  const _GroupForm({required this.form});
  final ScriptGroupFormData form;

  @override
  ConsumerState<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends ConsumerState<_GroupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _indexCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.form.name);
    _indexCtrl = TextEditingController(text: widget.form.index.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _indexCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    widget.form.name = _nameCtrl.text.trim();
    widget.form.index = int.tryParse(_indexCtrl.text.trim()) ?? 0;
    final repo = ref.read(scriptRepositoryProvider);
    try {
      final message = widget.form.isEdit
          ? await repo.updateGroup(widget.form)
          : await repo.createGroup(widget.form);
      await ref.read(scriptGroupListProvider.notifier).refresh();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.form.isEdit
                  ? l.tr('scripts.editGroup')
                  : l.tr('scripts.addGroup'),
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '分组名称',
                style: TextStyle(
                  color: c.softMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextFormField(
              controller: _nameCtrl,
              cursorColor: c.primary,
              style: TextStyle(color: c.text, fontSize: 14),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? l.tr('scripts.validation.groupName')
                  : null,
              decoration: _decoration(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '序号',
                style: TextStyle(
                  color: c.softMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextFormField(
              controller: _indexCtrl,
              cursorColor: c.primary,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: _decoration(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.strongBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      l.tr('common.cancel'),
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.fontOnPrimary,
                            ),
                          )
                        : Text(
                            l.tr('common.save'),
                            style: TextStyle(
                              color: c.fontOnPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration() {
    final c = context.colors;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: c.chip,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.primary, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.danger),
      ),
    );
  }
}
