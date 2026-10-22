import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/desktop_text_files.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_dropdown_menu.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_script_catalog_provider.dart';
import '../../state/plus_info_notifier.dart';
import '../order/order_layout.dart';
import 'desktop_script_dialogs.dart';
import 'script_model.dart';

class DesktopScriptsPage extends ConsumerStatefulWidget {
  const DesktopScriptsPage({super.key});
  @override
  ConsumerState<DesktopScriptsPage> createState() => _DesktopScriptsPageState();
}

class _DesktopScriptsPageState extends ConsumerState<DesktopScriptsPage> {
  final _search = TextEditingController();
  final _selected = <String>{};
  String _group = 'default';
  int _page = 1, _size = 20;
  List<ScriptModel>? _order;
  int _revision = 0;
  bool _busy = false;
  String? _error;

  void _clearSearch() => setState(() {
    _search.clear();
    _page = 1;
  });
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _mutate(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      ref.invalidate(desktopTerminalScriptCatalogProvider);
      if (mounted) setState(() => _selected.clear());
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ScriptModel? script]) => showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DesktopScriptDialog(script: script, group: _group),
  );

  Future<void> _delete(List<ScriptModel> scripts) async {
    if (!await managementConfirm(
          context,
          mx(
            context,
            '确认删除脚本：${scripts.map((s) => s.name).join('、')}？',
            'Delete scripts: ${scripts.map((s) => s.name).join(', ')}?',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _mutate(() async {
      final repo = ref.read(scriptRepositoryProvider);
      if (scripts.length == 1) {
        await repo.deleteScript(scripts.single.id);
      } else {
        await repo.batchDeleteScripts(scripts.map((s) => s.id).toList());
      }
    });
  }

  Future<void> _menu(String action) async {
    final catalog = ref.read(desktopTerminalScriptCatalogProvider).valueOrNull;
    if (catalog == null) return;
    switch (action) {
      case 'import':
        await showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const DesktopScriptImportDialog(),
        );
      case 'export':
        try {
          final scripts = catalog.scripts.where((s) => !s.isBuiltin).toList();
          if (scripts.isEmpty) {
            managementNotice(
              context,
              mx(context, '暂无可导出的脚本', 'No scripts to export'),
            );
            return;
          }
          await saveDesktopTextFile(
            'easynode-scripts-${DateTime.now().millisecondsSinceEpoch}.json',
            const JsonEncoder.withIndent('  ').convert([
              for (final s in scripts)
                {
                  'name': s.name,
                  'description': s.description,
                  'command': s.command,
                  'group': s.group,
                  'useBase64': s.useBase64,
                },
            ]),
          );
        } catch (e) {
          if (mounted) setState(() => _error = managementError(e));
        }
      case 'groups':
        await showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const DesktopScriptGroupsDialog(),
        );
      case 'order':
        setState(() {
          _search.clear();
          _selected.clear();
          _revision = catalog.order.revision;
          _order = catalog.scripts.where((s) => s.group == _group).toList();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopTerminalScriptCatalogProvider);
    final catalog = state.valueOrNull;
    final scripts = catalog?.scripts ?? [];
    final groups = catalog?.groups ?? [];
    final group = groups.any((g) => g.id == _group)
        ? _group
        : groups.firstOrNull?.id ?? 'default';
    if (group != _group) _group = group;
    final query = _search.text.trim().toLowerCase();
    final filtered = scripts
        .where(
          (s) =>
              s.group == group &&
              [
                s.name,
                s.description,
                s.command,
              ].any((v) => v.toLowerCase().contains(query)),
        )
        .toList();
    final page = math.min(_page, math.max(1, (filtered.length / _size).ceil()));
    final visible = filtered.skip((page - 1) * _size).take(_size).toList();
    final selectable = visible.where((s) => !s.isBuiltin).toList();
    final plus = ref.watch(isPlusActiveProvider);
    return ManagementPage(
      busy: _busy || state.isLoading,
      error: _error ?? (state.hasError ? managementError(state.error!) : null),
      toolbar: _order != null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    mx(context, '拖动整行调整脚本顺序', 'Drag rows to reorder scripts'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                ManagementButton(
                  label: mx(context, '取消', 'Cancel'),
                  onPressed: _busy ? null : () => setState(() => _order = null),
                ),
                const SizedBox(width: 8),
                ManagementButton(
                  label: mx(context, '保存顺序', 'Save order'),
                  primary: true,
                  onPressed: _busy
                      ? null
                      : () => _mutate(() async {
                          await ref
                              .read(scriptRepositoryProvider)
                              .updateOrder(_revision, [
                                OrderChange(
                                  scope: 'groupItems',
                                  groupId: group,
                                  orderedIds: _order!.map((s) => s.id).toList(),
                                ),
                              ]);
                          if (mounted) setState(() => _order = null);
                        }),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape &&
                          _search.text.isNotEmpty) {
                        _clearSearch();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const Key('scripts-search'),
                      controller: _search,
                      style: const TextStyle(fontSize: 13),
                      onChanged: (_) => setState(() => _page = 1),
                      decoration:
                          desktopInputDecoration(
                            context,
                            hint: mx(
                              context,
                              '搜索名称、描述或指令',
                              'Search name, description or command',
                            ),
                          ).copyWith(
                            prefixIcon: const Icon(Icons.search, size: 17),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: mx(
                                      context,
                                      '清空搜索',
                                      'Clear search',
                                    ),
                                    onPressed: _clearSearch,
                                    icon: const Icon(Icons.close, size: 15),
                                  ),
                          ),
                    ),
                  ),
                ),
                const Spacer(),
                if (state.hasError)
                  ManagementLink(
                    label: mx(context, '重试', 'Retry'),
                    onPressed: () =>
                        ref.invalidate(desktopTerminalScriptCatalogProvider),
                  ),
                ManagementButton(
                  key: const Key('script-add'),
                  label: mx(context, '添加脚本', 'Add script'),
                  icon: Icons.add,
                  primary: true,
                  onPressed: _busy ? null : () => _edit(),
                ),
                const SizedBox(width: 8),
                DesktopDropdownMenu<String>(
                  tooltip: mx(context, '更多操作', 'More actions'),
                  items: [
                    DesktopDropdownItem(
                      value: 'import',
                      label: mx(context, '导入脚本', 'Import scripts'),
                      icon: Icons.upload,
                      enabled: plus,
                    ),
                    DesktopDropdownItem(
                      value: 'export',
                      label: mx(context, '导出脚本', 'Export scripts'),
                      icon: Icons.download,
                      enabled: plus,
                    ),
                    DesktopDropdownItem(
                      value: 'groups',
                      label: mx(context, '分组管理', 'Manage groups'),
                      icon: Icons.folder_open,
                      enabled: plus,
                      divided: true,
                    ),
                    DesktopDropdownItem(
                      value: 'order',
                      label: mx(context, '调整顺序', 'Reorder'),
                      icon: Icons.swap_vert,
                      enabled: group != 'builtin',
                    ),
                  ],
                  onSelected: _menu,
                ),
              ],
            ),
      footer: _order != null
          ? null
          : ManagementPagination(
              total: filtered.length,
              page: page,
              pageSize: _size,
              onPage: (v) => setState(() => _page = v),
              onPageSize: (v) => setState(() {
                _size = v;
                _page = 1;
              }),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selected.isNotEmpty && _order == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: context.colors.accentSoft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      mx(
                        context,
                        '已选择 ${_selected.length} 个脚本',
                        '${_selected.length} selected',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  ManagementLink(
                    label: mx(context, '删除', 'Delete'),
                    danger: true,
                    onPressed: _busy
                        ? null
                        : () => _delete(
                            scripts
                                .where(
                                  (s) =>
                                      _selected.contains(s.id) && !s.isBuiltin,
                                )
                                .toList(),
                          ),
                  ),
                  ManagementLink(
                    label: mx(context, '取消选择', 'Clear selection'),
                    onPressed: () => setState(_selected.clear),
                  ),
                ],
              ),
            ),
          ManagementTabs<String>(
            options: {for (final g in groups) g.id: g.displayName},
            value: group,
            height: 42,
            horizontalPadding: 18,
            fontWeight: FontWeight.w600,
            onChanged: _order != null
                ? null
                : (value) => setState(() {
                    _group = value;
                    _page = 1;
                    _selected.clear();
                  }),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _order != null
                ? ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: _order!.length,
                    onReorderItem: (oldIndex, newIndex) {
                      if (_busy) return;
                      setState(() {
                        _order!.insert(newIndex, _order!.removeAt(oldIndex));
                      });
                    },
                    itemBuilder: (context, i) => ReorderableDragStartListener(
                      key: ValueKey(_order![i].id),
                      index: i,
                      enabled: !_busy,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.colors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.drag_indicator, size: 16),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                _order![i].name,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _order![i].description,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ManagementTable(
                    empty: mx(context, '暂无脚本', 'No scripts'),
                    columns: [
                      ManagementColumn(
                        '',
                        width: 48,
                        heading: Checkbox(
                          value:
                              selectable.isNotEmpty &&
                              selectable.every((s) => _selected.contains(s.id)),
                          onChanged: selectable.isEmpty
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _selected.addAll(
                                      selectable.map((s) => s.id),
                                    );
                                  } else {
                                    _selected.removeAll(
                                      selectable.map((s) => s.id),
                                    );
                                  }
                                }),
                        ),
                      ),
                      ManagementColumn(mx(context, '名称', 'Name'), width: 180),
                      ManagementColumn(
                        mx(context, '描述', 'Description'),
                        width: 180,
                      ),
                      ManagementColumn(
                        mx(context, '指令内容', 'Command'),
                        width: 240,
                      ),
                      ManagementColumn(
                        mx(context, '编码方式', 'Encoding'),
                        width: 130,
                      ),
                      ManagementColumn.actions(
                        mx(context, '操作', 'Actions'),
                        width: 115,
                      ),
                    ],
                    rows: [
                      for (final s in visible)
                        [
                          Checkbox(
                            value: _selected.contains(s.id),
                            onChanged: s.isBuiltin || _busy
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(s.id);
                                    } else {
                                      _selected.remove(s.id);
                                    }
                                  }),
                          ),
                          Text(
                            s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            s.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Tooltip(
                            message: s.command,
                            child: Text(
                              s.command,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            s.useBase64
                                ? 'Base64'
                                : mx(context, '直接发送', 'Direct'),
                          ),
                          s.isBuiltin
                              ? const Text('—')
                              : Row(
                                  children: [
                                    ManagementLink(
                                      label: mx(context, '编辑', 'Edit'),
                                      onPressed: _busy ? null : () => _edit(s),
                                    ),
                                    if (s.id != 'own')
                                      DesktopDropdownMenu<String>(
                                        tooltip: mx(
                                          context,
                                          '更多操作',
                                          'More actions',
                                        ),
                                        buttonSize: const Size(28, 30),
                                        items: [
                                          DesktopDropdownItem(
                                            value: 'delete',
                                            label: mx(
                                              context,
                                              '删除脚本',
                                              'Delete script',
                                            ),
                                            icon: Icons.delete_outline,
                                            danger: true,
                                          ),
                                        ],
                                        onSelected: (_) => _delete([s]),
                                      ),
                                  ],
                                ),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
