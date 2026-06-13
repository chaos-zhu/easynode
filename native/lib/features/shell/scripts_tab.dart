import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../features/scripts/script_form_page.dart';
import '../../features/scripts/script_group_model.dart';
import '../../features/scripts/script_groups_page.dart';
import '../../features/scripts/script_model.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/script_group_list_notifier.dart';
import '../../state/script_list_notifier.dart';
import 'tab_header.dart';

import '../../core/ui/app_color_theme.dart';

/// Script-specific accent — distinct from the global `AppColorTheme.accent`.
const _kScriptAccent = Color(0xFF6F4B2A);
const _kScriptAccentSoft = Color(0xFFEEDCB5);
const _kScriptSuccessSoft = Color(0x225A8E3A);

/// Third bottom-nav tab — scripts library. Mirrors design node `Zhupt` and
/// feature parity with web `web/src/views/scripts/index.vue`: search + group
/// chips + card list with copy/edit/delete actions. State is sourced from
/// the shared [scriptListProvider] / [scriptGroupListProvider] so other
/// features (e.g. terminal quick-actions) can read the same snapshot.
class ScriptsTab extends ConsumerStatefulWidget {
  const ScriptsTab({super.key});

  @override
  ConsumerState<ScriptsTab> createState() => _ScriptsTabState();
}

class _ScriptsTabState extends ConsumerState<ScriptsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedGroupId;
  String _query = '';
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await runRefreshWithFeedback(
      context,
      () => Future.wait([
        ref.read(scriptListProvider.notifier).refresh(throwOnError: true),
        ref
            .read(scriptGroupListProvider.notifier)
            .refresh(throwOnError: true),
      ]),
    );
  }

  Future<void> _openForm({ScriptModel? script}) async {
    final l = AppLocalizations.of(context);
    if (script != null && script.isBuiltin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.tr('scripts.builtinReadonly'))));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ScriptFormPage(script: script, defaultGroup: _selectedGroupId),
      ),
    );
  }

  Future<void> _openGroups() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ScriptGroupsPage()));
  }

  Future<void> _copyCommand(ScriptModel script) async {
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: script.command));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.tr('scripts.commandCopied'))));
  }

  Future<void> _confirmDelete(ScriptModel script) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('scripts.deleteScriptTitle')),
        content: Text(l.trf('scripts.deleteScriptBody', [script.name])),
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
    try {
      final message = await ref
          .read(scriptRepositoryProvider)
          .deleteScript(script.id);
      await ref.read(scriptListProvider.notifier).refresh();
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
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scriptsAsync = ref.watch(scriptListProvider);
    final groupsAsync = ref.watch(scriptGroupListProvider);
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.canvas,
      body: RefreshIndicator(
        color: c.primary,
        backgroundColor: c.card,
        displacement: 30,
        edgeOffset: 6,
        strokeWidth: 2,
        onRefresh: _refresh,
        child: _buildBody(scriptsAsync, groupsAsync),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<ScriptModel>> scriptsAsync,
    AsyncValue<List<ScriptGroupModel>> groupsAsync,
  ) {
    final l = AppLocalizations.of(context);
    return scriptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        if (error is UnauthorizedFailure) return const SizedBox.shrink();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 56),
            Center(
              child: Text(
                l.trf('scripts.loadFailed', [error.toString()]),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(l.tr('common.retry')),
              ),
            ),
          ],
        );
      },
      data: (scripts) {
        final groups = groupsAsync.valueOrNull ?? const <ScriptGroupModel>[];
        final searched = _searched(scripts);
        final effectiveGroupId = _effectiveGroupId(groups);
        final filtered = _filterByGroup(searched, effectiveGroupId);
        return Column(
          children: [
            TabHeader(
              title: l.tr('tabs.scripts'),
              actions: [
                _HeaderIconButton(
                  tooltip: _searchVisible
                      ? l.tr('common.closeSearch')
                      : l.tr('common.search'),
                  icon: _searchVisible ? Icons.close : Icons.search,
                  onPressed: _toggleSearch,
                ),
                const SizedBox(width: 4),
                _HeaderIconButton(
                  tooltip: l.tr('scripts.groupsManage'),
                  icon: Icons.account_tree_outlined,
                  onPressed: _openGroups,
                ),
                const SizedBox(width: 4),
                Material(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openForm(),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.add, size: 20, color: context.colors.fontOnPrimary),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: _searchVisible
                          ? Padding(
                              key: const ValueKey('search'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SizedBox(
                                height: 44,
                                child: TextField(
                                  controller: _searchCtrl,
                                  autofocus: true,
                                  cursorColor: context.colors.primary,
                                  style: TextStyle(
                                    color: context.colors.text,
                                    fontSize: 14,
                                  ),
                                  decoration: _searchFieldDecoration(context, l)
                                      .copyWith(
                                        hintText: l.tr('scripts.searchHint'),
                                      ),
                                  onChanged: (v) => setState(
                                    () => _query = v.trim().toLowerCase(),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('search-empty'),
                              width: double.infinity,
                            ),
                    ),
                  ),
                  _GroupChips(
                    groups: groups,
                    scripts: searched,
                    selectedGroupId: effectiveGroupId,
                    onSelected: (id) => setState(() => _selectedGroupId = id),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                children: [
                  if (scripts.isEmpty)
                    _MessageState(message: l.tr('scripts.emptyHint'))
                  else if (filtered.isEmpty)
                    _MessageState(message: l.tr('scripts.emptyFiltered'))
                  else
                    for (var i = 0; i < filtered.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ScriptCard(
                          script: filtered[i],
                          groupName: _groupName(filtered[i], groups),
                          onCopy: () => _copyCommand(filtered[i]),
                          onEdit: filtered[i].isBuiltin
                              ? null
                              : () => _openForm(script: filtered[i]),
                          onDelete: filtered[i].isBuiltin
                              ? null
                              : () => _confirmDelete(filtered[i]),
                        ),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<ScriptModel> _searched(List<ScriptModel> scripts) {
    if (_query.isEmpty) return scripts;
    return scripts
        .where((s) {
          final haystack = '${s.name} ${s.description} ${s.command}'
              .toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }

  String? _effectiveGroupId(List<ScriptGroupModel> groups) {
    if (_selectedGroupId == null) return null;
    if (groups.any((g) => g.id == _selectedGroupId)) return _selectedGroupId;
    return null;
  }

  List<ScriptModel> _filterByGroup(List<ScriptModel> scripts, String? groupId) {
    if (groupId == null) return scripts;
    return scripts.where((s) => s.group == groupId).toList(growable: false);
  }

  String _groupName(ScriptModel script, List<ScriptGroupModel> groups) {
    for (final g in groups) {
      if (g.id == script.group) return g.displayName;
    }
    return script.group;
  }
}

class _GroupChips extends StatelessWidget {
  const _GroupChips({
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
    final l = AppLocalizations.of(context);
    final counts = <String, int>{for (final g in groups) g.id: 0};
    for (final s in scripts) {
      counts[s.group] = (counts[s.group] ?? 0) + 1;
    }
    final visible = groups
        .where((g) => (counts[g.id] ?? 0) > 0)
        .toList(growable: false);
    if (visible.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: visible.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _Chip(
                label: l.tr('common.all'),
                count: scripts.length,
                selected: selectedGroupId == null,
                onTap: () => onSelected(null),
              );
            }
            final g = visible[i - 1];
            return _Chip(
              label: g.displayName,
              count: counts[g.id] ?? 0,
              selected: selectedGroupId == g.id,
              onTap: () => onSelected(g.id),
            );
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? c.primary : Colors.transparent;
    final fg = selected ? c.fontOnPrimary : c.text;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? BorderSide.none
            : BorderSide(color: c.strongBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? c.fontOnPrimary.withValues(alpha: 0.20)
                      : c.chip,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: selected ? c.fontOnPrimary : c.softMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({
    required this.script,
    required this.groupName,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final ScriptModel script;
  final String groupName;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
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
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (script.useBase64) const _Base64Chip() else const _PlainChip(),
            ],
          ),
          if (script.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              script.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                height: 1.4,
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
                size: 13,
                color: c.softMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.softMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ActionIcon(
                tooltip: AppLocalizations.of(context).tr('scripts.action.copy'),
                icon: Icons.copy,
                color: c.muted,
                onTap: onCopy,
              ),
              if (onEdit != null)
                _ActionIcon(
                  tooltip: AppLocalizations.of(
                    context,
                  ).tr('scripts.action.edit'),
                  icon: Icons.edit_outlined,
                  color: c.muted,
                  onTap: onEdit,
                ),
              if (onDelete != null)
                _ActionIcon(
                  tooltip: AppLocalizations.of(
                    context,
                  ).tr('scripts.action.delete'),
                  icon: Icons.delete_outline,
                  color: c.danger,
                  onTap: onDelete,
                ),
            ],
          ),
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
    final c = context.colors;
    final firstLine = command.split('\n').first.trim();
    final hasMore = command.contains('\n');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Text(
            '\$',
            style: TextStyle(
              color: c.softMuted,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasMore ? '$firstLine …' : firstLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
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

class _Base64Chip extends StatelessWidget {
  const _Base64Chip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kScriptAccentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code, size: 11, color: _kScriptAccent),
          SizedBox(width: 4),
          Text(
            'Base64',
            style: TextStyle(
              color: _kScriptAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainChip extends StatelessWidget {
  const _PlainChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kScriptSuccessSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.send_outlined, size: 11, color: context.colors.success),
          const SizedBox(width: 4),
          Text(
            '直接发送',
            style: TextStyle(
              color: context.colors.success,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(child: Icon(icon, size: 18, color: color)),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 22,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: context.colors.muted, size: 22),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted),
        ),
      ),
    );
  }
}

InputDecoration _searchFieldDecoration(BuildContext context, AppLocalizations l) {
  final c = context.colors;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: c.card,
    prefixIcon: const Icon(Icons.search, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    hintStyle: TextStyle(color: c.softMuted, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
  );
}

