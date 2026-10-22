import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/desktop_text_files.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_popover.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_script_catalog_provider.dart';
import '../../state/plus_info_notifier.dart';
import '../order/order_layout.dart';
import 'script_group_model.dart';
import 'script_model.dart';
import 'script_repository.dart';

/// Web's compact library import action, shared by execution forms.
class DesktopScriptImportButton extends StatelessWidget {
  const DesktopScriptImportButton({
    super.key,
    required this.scripts,
    required this.onSelected,
    this.height = 32,
  });
  final List<ScriptModel> scripts;
  final ValueChanged<ScriptModel>? onSelected;
  final double height;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => TextButton(
      style: TextButton.styleFrom(
        foregroundColor: context.colors.accent,
        textStyle: const TextStyle(fontSize: 13),
        padding: EdgeInsets.zero,
        minimumSize: Size(0, height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: scripts.isEmpty || onSelected == null
          ? null
          : () async {
              final script = await showDesktopPopover<ScriptModel>(
                context: anchor,
                width: 260,
                maxHeight: MediaQuery.sizeOf(context).height * .5,
                builder: (context) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(5),
                  children: [
                    for (final s in scripts)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.text,
                          textStyle: const TextStyle(fontSize: 13),
                          alignment: Alignment.centerLeft,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, s),
                        child: Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
              if (script != null && anchor.mounted) onSelected!(script);
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mx(context, '从脚本库导入', 'Import from library')),
          const Icon(Icons.keyboard_arrow_down, size: 15),
        ],
      ),
    ),
  );
}

class DesktopScriptDialog extends ConsumerStatefulWidget {
  const DesktopScriptDialog({
    super.key,
    this.script,
    this.command,
    this.group,
    this.base64 = false,
  });
  final ScriptModel? script;
  final String? command, group;
  final bool base64;
  @override
  ConsumerState<DesktopScriptDialog> createState() =>
      _DesktopScriptDialogState();
}

class _DesktopScriptDialogState extends ConsumerState<DesktopScriptDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.script?.name);
  late final _description = TextEditingController(
    text: widget.script?.description,
  );
  late final _command = TextEditingController(
    text: widget.script?.command ?? widget.command,
  );
  late String _group =
      widget.script?.group ??
      (widget.group == 'builtin' ? 'default' : widget.group ?? 'default');
  late bool _base64 = widget.script?.useBase64 ?? widget.base64;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _description, _command]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = ScriptFormData(
        id: widget.script?.id,
        name: _name.text.trim(),
        description: _description.text.trim(),
        command: _command.text,
        group: _group,
        useBase64: _base64,
      );
      final repo = ref.read(scriptRepositoryProvider);
      if (data.isEdit) {
        await repo.updateScript(data);
      } else {
        await repo.createScript(data);
      }
      ref.invalidate(desktopTerminalScriptCatalogProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _input(
    String label,
    TextEditingController c, {
    int lines = 1,
    bool required = false,
    String? hint,
  }) => ManagementField(
    label: label,
    child: TextFormField(
      controller: c,
      enabled: !_busy,
      maxLines: lines,
      style: TextStyle(
        fontSize: 13,
        fontFamily: lines > 1 ? 'monospace' : null,
      ),
      decoration: desktopInputDecoration(context, hint: hint),
      autocorrect: false,
      validator: (v) => required && v!.trim().isEmpty
          ? mx(context, '此项必填', 'Required')
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopTerminalScriptCatalogProvider);
    final groups =
        state.valueOrNull?.groups.where((g) => !g.isBuiltin).toList() ?? [];
    return DesktopManagementDialog(
      width: 600,
      topAligned: true,
      busy: _busy,
      title: widget.script == null
          ? mx(context, '添加脚本', 'Add script')
          : mx(context, '编辑脚本', 'Edit script'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null || state.hasError)
              ManagementError(
                message: _error ?? managementError(state.error!),
                onRetry: state.hasError
                    ? () => ref.invalidate(desktopTerminalScriptCatalogProvider)
                    : null,
              ),
            ManagementPair(
              left: ManagementField(
                label: mx(context, '分组', 'Group'),
                child: FormField<String>(
                  initialValue: _group,
                  validator: (_) => groups.any((g) => g.id == _group)
                      ? null
                      : mx(context, '选择一个分组', 'Select a group'),
                  builder: (field) => DesktopSelect(
                    options: {for (final g in groups) g.id: g.displayName},
                    values: [_group],
                    errorText: field.errorText,
                    enabled: !_busy,
                    onSelected: (v) {
                      field.didChange(v);
                      setState(() => _group = v);
                    },
                  ),
                ),
              ),
              right: _input(
                mx(context, '名称', 'Name'),
                _name,
                required: true,
                hint: mx(context, '输入脚本名称', 'Enter script name'),
              ),
            ),
            _input(
              mx(context, '描述', 'Description'),
              _description,
              hint: mx(
                context,
                '简要描述脚本用途（可选）',
                'Describe what the script does (optional)',
              ),
            ),
            _input(
              mx(context, '脚本内容', 'Script content'),
              _command,
              lines: 7,
              required: true,
              hint: mx(context, '输入 Shell 脚本', 'Enter Shell script'),
            ),
            ManagementField(
              label: mx(context, '编码方式', 'Execution mode'),
              child: DesktopSelect(
                options: {
                  'direct': mx(context, '直接发送', 'Send directly'),
                  'base64': mx(context, 'Base64 编码', 'Base64 encoding'),
                },
                descriptions: {
                  'direct': mx(
                    context,
                    '适合单行指令；多行脚本会逐行发送。',
                    'For simple commands; multiline scripts are sent line by line.',
                  ),
                  'base64': mx(
                    context,
                    '适合多行复杂脚本，避免转义与换行问题。',
                    'For multiline scripts; avoids quoting and line ending issues.',
                  ),
                },
                values: [_base64 ? 'base64' : 'direct'],
                enabled: !_busy,
                onSelected: (v) => setState(() => _base64 = v == 'base64'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ManagementButton(
          label: mx(context, '取消', 'Cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        ManagementButton(
          label: widget.script == null
              ? mx(context, '创建脚本', 'Create script')
              : mx(context, '保存修改', 'Save changes'),
          primary: true,
          onPressed: _busy || state.isLoading ? null : _save,
        ),
      ],
    );
  }
}

class DesktopScriptGroupsDialog extends ConsumerStatefulWidget {
  const DesktopScriptGroupsDialog({super.key});
  @override
  ConsumerState<DesktopScriptGroupsDialog> createState() =>
      _DesktopScriptGroupsDialogState();
}

class _DesktopScriptGroupsDialogState
    extends ConsumerState<DesktopScriptGroupsDialog> {
  bool _busy = false;
  String? _error;
  List<ScriptGroupModel>? _draft;
  int _revision = 0;
  Future<void> _action(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      ref.invalidate(desktopTerminalScriptCatalogProvider);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ScriptGroupModel? group]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScriptGroupNameDialog(group: group),
    );
    if (saved == true) ref.invalidate(desktopTerminalScriptCatalogProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopTerminalScriptCatalogProvider);
    final catalog = state.valueOrNull;
    final groups = catalog?.groups ?? [];
    final plus = ref.watch(isPlusActiveProvider);
    return DesktopManagementDialog(
      width: 660,
      topAligned: true,
      busy: _busy,
      title: mx(context, '脚本分组管理', 'Script groups'),
      body: SizedBox(
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null || state.hasError)
              ManagementError(message: _error ?? managementError(state.error!)),
            if (!plus)
              Text(
                mx(context, '分组管理需要 Plus', 'Group management requires Plus'),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _draft == null
                        ? mx(
                            context,
                            '共 ${groups.length} 个分组',
                            '${groups.length} groups',
                          )
                        : mx(
                            context,
                            '拖动整行调整分组顺序',
                            'Drag rows to reorder groups',
                          ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (_draft == null) ...[
                  ManagementButton(
                    label: mx(context, '调整顺序', 'Reorder'),
                    onPressed:
                        !plus ||
                            _busy ||
                            groups.where((g) => !g.isBuiltin).length < 2
                        ? null
                        : () => setState(() {
                            _revision = catalog!.order.revision;
                            _draft = groups.where((g) => !g.isBuiltin).toList();
                          }),
                  ),
                  const SizedBox(width: 8),
                  ManagementButton(
                    label: mx(context, '添加分组', 'Add group'),
                    primary: true,
                    icon: Icons.add,
                    onPressed: !plus || _busy ? null : () => _edit(),
                  ),
                ] else ...[
                  ManagementButton(
                    label: mx(context, '取消', 'Cancel'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _draft = null),
                  ),
                  const SizedBox(width: 8),
                  ManagementButton(
                    label: mx(context, '保存顺序', 'Save order'),
                    primary: true,
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                            await ref
                                .read(scriptRepositoryProvider)
                                .updateOrder(_revision, [
                                  OrderChange(
                                    scope: 'groups',
                                    orderedIds: [
                                      ..._draft!.map((g) => g.id),
                                      ...groups
                                          .where((g) => g.isBuiltin)
                                          .map((g) => g.id),
                                    ],
                                  ),
                                ]);
                            if (mounted) setState(() => _draft = null);
                          }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _draft != null
                  ? ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: _draft!.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (_busy) return;
                        setState(() {
                          _draft!.insert(newIndex, _draft!.removeAt(oldIndex));
                        });
                      },
                      itemBuilder: (context, i) => ReorderableDragStartListener(
                        key: ValueKey(_draft![i].id),
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
                              const SizedBox(width: 12),
                              Text(_draft![i].displayName),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ManagementTable(
                      columns: [
                        ManagementColumn(
                          mx(context, '分组名称', 'Group'),
                          width: 220,
                        ),
                        ManagementColumn(
                          mx(context, '脚本数量', 'Scripts'),
                          width: 100,
                        ),
                        ManagementColumn.actions(
                          mx(context, '操作', 'Actions'),
                          width: 140,
                        ),
                      ],
                      rows: [
                        for (final g in groups)
                          [
                            Text(g.displayName),
                            Tooltip(
                              message:
                                  (catalog?.scripts
                                      .where((s) => s.group == g.id)
                                      .map((s) => '${s.name} ${s.description}')
                                      .join('\n') ??
                                  ''),
                              child: Text(
                                '${catalog?.scripts.where((s) => s.group == g.id).length ?? 0}',
                              ),
                            ),
                            g.isBuiltin
                                ? Text(mx(context, '固定', 'Fixed'))
                                : Row(
                                    children: [
                                      ManagementLink(
                                        label: mx(context, '编辑', 'Edit'),
                                        onPressed: plus && !_busy
                                            ? () => _edit(g)
                                            : null,
                                      ),
                                      if (!g.isDefault)
                                        ManagementLink(
                                          label: mx(context, '删除', 'Delete'),
                                          danger: true,
                                          onPressed: !plus || _busy
                                              ? null
                                              : () async {
                                                  if (await managementConfirm(
                                                        context,
                                                        mx(
                                                          context,
                                                          '删除分组「${g.displayName}」？脚本将移至默认分组。',
                                                          'Delete ${g.displayName}? Scripts will move to the default group.',
                                                        ),
                                                      ) &&
                                                      mounted) {
                                                    await _action(() async {
                                                      await ref
                                                          .read(
                                                            scriptRepositoryProvider,
                                                          )
                                                          .deleteGroup(g.id);
                                                    });
                                                  }
                                                },
                                        ),
                                    ],
                                  ),
                          ],
                      ],
                    ),
            ),
            if (_draft != null && groups.any((g) => g.isBuiltin))
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  mx(context, '内置分组固定在末尾', 'The built-in group remains last'),
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        ManagementButton(
          label: mx(context, '关闭', 'Close'),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _ScriptGroupNameDialog extends ConsumerStatefulWidget {
  const _ScriptGroupNameDialog({this.group});
  final ScriptGroupModel? group;
  @override
  ConsumerState<_ScriptGroupNameDialog> createState() =>
      _ScriptGroupNameDialogState();
}

class _ScriptGroupNameDialogState
    extends ConsumerState<_ScriptGroupNameDialog> {
  late final _name = TextEditingController(text: widget.group?.name);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _name.text.trim().isEmpty) {
      setState(() => _error = mx(context, '请输入分组名称', 'Enter a group name'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = ScriptGroupFormData(
        id: widget.group?.id,
        name: _name.text.trim(),
      );
      final repo = ref.read(scriptRepositoryProvider);
      if (form.isEdit) {
        await repo.updateGroup(form);
      } else {
        await repo.createGroup(form);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 420,
    busy: _busy,
    title: widget.group == null
        ? mx(context, '添加分组', 'Add group')
        : mx(context, '编辑分组', 'Edit group'),
    body: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ManagementError(message: _error!),
        TextField(
          controller: _name,
          autofocus: true,
          enabled: !_busy,
          decoration: desktopInputDecoration(context),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: mx(context, '保存', 'Save'),
        primary: true,
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}

/// Validates files before submitting any import, and removes duplicate commands
/// both against the current catalog and within the selected files.
List<Map<String, dynamic>> prepareScriptImport(
  Object? input,
  ScriptCatalog catalog,
  String group,
) {
  final entries = <Map<String, dynamic>>[];
  final commands = catalog.scripts.map((s) => s.command).toSet();
  final ids = catalog.scripts.map((s) => s.id).toSet();
  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    if (value is! Map ||
        value['command'] is! String ||
        (value['command'] as String).trim().isEmpty) {
      throw const FormatException('Invalid script record');
    }
    final command = value['command'] as String;
    if (ids.contains(value['_id']) ||
        ids.contains(value['id']) ||
        !commands.add(command)) {
      return;
    }
    entries.add({
      'name': value['name']?.toString().isNotEmpty == true
          ? value['name'].toString()
          : command.substring(0, command.length.clamp(0, 15)),
      'description': value['description']?.toString() ?? '',
      'command': command,
      'group': group,
      'useBase64': value['useBase64'] == true,
    });
  }

  visit(input);
  return entries;
}

class DesktopScriptImportDialog extends ConsumerStatefulWidget {
  const DesktopScriptImportDialog({super.key});
  @override
  ConsumerState<DesktopScriptImportDialog> createState() =>
      _DesktopScriptImportDialogState();
}

class _DesktopScriptImportDialogState
    extends ConsumerState<DesktopScriptImportDialog> {
  final _text = TextEditingController();
  String _group = 'default';
  bool _manual = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import({bool file = false}) async {
    final catalog = ref.read(desktopTerminalScriptCatalogProvider).valueOrNull;
    if (catalog == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Object input;
      if (file) {
        final texts = await pickDesktopTextFiles(multiple: true);
        if (texts == null) return;
        if (!mounted) return;
        input = texts.map(jsonDecode).toList();
      } else {
        input = _text.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(
              (s) => {
                'command': s,
                'description': mx(context, '手动输入', 'Manual input'),
              },
            )
            .toList();
      }
      if (!mounted) return;
      final scripts = prepareScriptImport(input, catalog, _group);
      if (scripts.isEmpty) {
        throw StateError(
          mx(
            context,
            '没有新脚本可导入，内容为空或已存在。',
            'No new scripts to import. Content is empty or already exists.',
          ),
        );
      }
      final count = await ref
          .read(scriptRepositoryProvider)
          .importScripts(scripts);
      ref.invalidate(desktopTerminalScriptCatalogProvider);
      if (mounted) {
        managementNotice(
          context,
          mx(context, '成功导入 $count 条脚本', 'Imported $count scripts'),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups =
        ref.watch(desktopTerminalScriptCatalogProvider).valueOrNull?.groups ??
        [];
    return DesktopManagementDialog(
      width: 600,
      topAligned: true,
      busy: _busy,
      title: mx(context, '导入脚本', 'Import scripts'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ManagementError(message: _error!),
          ManagementField(
            label: mx(context, '导入到', 'Import into'),
            child: DesktopSelect(
              options: {
                for (final g in groups)
                  if (!g.isBuiltin) g.id: g.displayName,
              },
              values: [_group],
              enabled: !_busy,
              onSelected: (v) => setState(() => _group = v),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ManagementButton(
                  label: mx(context, '选择 JSON 文件', 'Choose JSON files'),
                  icon: Icons.upload_file,
                  onPressed: _busy ? null : () => _import(file: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ManagementButton(
                  label: mx(context, '手动输入', 'Manual input'),
                  icon: Icons.edit_outlined,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _manual = true),
                ),
              ),
            ],
          ),
          if (_manual)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                controller: _text,
                enabled: !_busy,
                minLines: 12,
                maxLines: 18,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: desktopInputDecoration(
                  context,
                  hint: mx(
                    context,
                    '每行输入一条脚本指令',
                    'Enter one script command per line',
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        ManagementButton(
          label: mx(context, '取消', 'Cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        if (_manual)
          ManagementButton(
            label: mx(context, '导入脚本', 'Import scripts'),
            primary: true,
            onPressed: _busy ? null : () => _import(),
          ),
      ],
    );
  }
}
