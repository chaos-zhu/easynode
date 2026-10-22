import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../core/ui/desktop_select.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/api_providers.dart';
import '../../../state/plus_info_notifier.dart';
import '../../scripts/script_model.dart';
import '../../scripts/script_repository.dart';
import 'terminal_widgets.dart';
import 'terminal_text_prompt.dart';
import 'terminal_catalog_order.dart';

final desktopTerminalScriptCatalogProvider =
    FutureProvider.autoDispose<ScriptCatalog>((ref) async {
      final catalog = await ref.watch(scriptRepositoryProvider).fetchCatalog();
      return ScriptCatalog(
        groups: orderTerminalItems(
          catalog.groups,
          catalog.order.sections.map((s) => s.groupId),
          (g) => g.id,
        ),
        scripts: orderTerminalItems(
          catalog.scripts,
          catalog.order.sections.expand((s) => s.itemIds),
          (s) => s.id,
        ),
        order: catalog.order,
      );
    });
typedef DesktopScriptSend = void Function(String command, bool base64);

class DesktopTerminalScripts extends ConsumerStatefulWidget {
  const DesktopTerminalScripts({
    super.key,
    required this.onSend,
    this.initialDraft = '',
    this.onDraftChanged,
  });
  final String initialDraft;
  final ValueChanged<String>? onDraftChanged;
  final DesktopScriptSend onSend;
  @override
  ConsumerState<DesktopTerminalScripts> createState() =>
      _DesktopTerminalScriptsState();
}

class _DesktopTerminalScriptsState
    extends ConsumerState<DesktopTerminalScripts> {
  late final _editor = TextEditingController(text: widget.initialDraft);
  @override
  void initState() {
    super.initState();
    _editor.addListener(_draftChanged);
  }

  void _draftChanged() => widget.onDraftChanged?.call(_editor.text);
  String? _group;
  bool _base64 = false, _clear = false;
  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _send() {
    if (_editor.text.trim().isEmpty) return;
    widget.onSend(_editor.text, _base64);
    if (_clear) _editor.clear();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(desktopTerminalScriptCatalogProvider);
    final plus = ref.watch(isPlusActiveProvider);
    if (!plus) {
      return Center(
        child: Text(AppLocalizations.of(context).tr('plus.serverManagedTip')),
      );
    }
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(desktopTerminalScriptCatalogProvider),
          child: Text('${dt(context, 'retry')}: $e'),
        ),
      ),
      data: (catalog) {
        final group = _group ?? catalog.groups.firstOrNull?.id ?? 'default';
        final scripts = catalog.scripts.where((s) => s.group == group).toList();
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _scriptLibrary(catalog, group, scripts)),
              const SizedBox(width: 10),
              Expanded(child: _commandEditor(group)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(Widget child) => Container(
    height: 32,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: child,
  );

  Widget _scriptLibrary(
    ScriptCatalog catalog,
    String group,
    List<ScriptModel> scripts,
  ) => _box(
    Column(
      children: [
        _header(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in catalog.groups)
                  _groupPill(
                    item.name,
                    group == item.id,
                    () => setState(() => _group = item.id),
                  ),
                _groupPill(
                  dt(context, 'groups'),
                  false,
                  () => showAppDialog<void>(
                    context: context,
                    builder: (_) => const _ScriptGroupsDialog(),
                  ),
                  icon: Icons.settings_outlined,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              for (final script in scripts)
                _ScriptRow(
                  script: script,
                  onRun: () => widget.onSend(script.command, script.useBase64),
                  onEdit: script.isBuiltin
                      ? null
                      : () =>
                            editDesktopTerminalScript(context, script: script),
                  onToEditor: () {
                    _editor.text = script.command;
                    setState(() => _base64 = script.useBase64);
                  },
                ),
              if (group != 'builtin') _addScript(group),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _addScript(String group) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: CustomPaint(
      painter: _DashedBorder(context.colors.border),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: context.colors.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          onPressed: () => editDesktopTerminalScript(context, group: group),
          icon: const TerminalIcon(Icons.add, size: 14),
          label: Text(
            dt(context, 'newScript'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ),
  );

  Widget _commandEditor(String group) => _box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          Text(
            dt(context, 'editor'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editor,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.text,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.all(10),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: dt(context, 'commandHint'),
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: context.colors.softMuted,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: _sendActions(group),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sendActions(String group) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Flexible(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Builder(
            builder: (anchor) => TerminalMenuButton(
              outlined: true,
              dropdown: true,
              label: dt(context, _base64 ? 'base64Send' : 'directSend'),
              onPressed: () async {
                final result = await showTerminalMenu(anchor, [
                  TerminalMenuAction(
                    'direct',
                    dt(context, 'directSend'),
                    Icons.code,
                  ),
                  TerminalMenuAction(
                    'base64',
                    dt(context, 'base64Send'),
                    Icons.data_object,
                  ),
                ]);
                if (mounted && result != null) {
                  setState(() => _base64 = result == 'base64');
                }
              },
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _editor,
        builder: (context, value, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              style: _sendButtonStyle(false),
              onPressed: value.text.trim().isEmpty ? null : _send,
              child: Text(
                dt(context, 'send'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: context.colors.card.withValues(alpha: .3),
            ),
            Builder(
              builder: (anchor) => TextButton(
                style: _sendButtonStyle(true),
                onPressed: () => _sendOptions(anchor, group),
                child: const TerminalIcon(Icons.keyboard_arrow_down, size: 12),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  ButtonStyle _sendButtonStyle(bool menu) =>
      desktopButtonStyle(context, primary: true).copyWith(
        minimumSize: WidgetStatePropertyAll(Size(menu ? 24 : 0, 26)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: menu ? 6 : 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(menu ? 0 : 3),
              right: Radius.circular(menu ? 3 : 0),
            ),
          ),
        ),
      );

  Widget _box(Widget child) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: context.colors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: child,
  );

  Widget _groupPill(
    String label,
    bool active,
    VoidCallback action, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: active ? context.colors.accent : context.colors.text,
        backgroundColor: active
            ? context.colors.accent.withValues(alpha: .08)
            : Colors.transparent,
        minimumSize: const Size(0, 20),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: active
              ? context.colors.accent.withValues(alpha: .4)
              : context.colors.border,
        ),
        shape: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
      ),
      onPressed: action,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            TerminalIcon(icon, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _sendOptions(BuildContext anchor, String group) async {
    final result = await showTerminalMenu(anchor, [
      TerminalMenuAction(
        'save',
        dt(context, 'saveScript'),
        Icons.save_outlined,
      ),
      TerminalMenuAction(
        'clear',
        '${dt(context, 'clearAfterSend')}  ${_clear ? '✓' : ''}',
        Icons.clear_all,
      ),
    ]);
    if (!mounted) return;
    if (result == 'save') {
      await editDesktopTerminalScript(
        context,
        command: _editor.text,
        group: group,
        base64: _base64,
      );
    } else if (result == 'clear') {
      setState(() => _clear = !_clear);
    }
  }
}

class _ScriptRow extends StatefulWidget {
  const _ScriptRow({
    required this.script,
    required this.onRun,
    required this.onEdit,
    required this.onToEditor,
  });
  final ScriptModel script;
  final VoidCallback onRun, onToEditor;
  final VoidCallback? onEdit;
  @override
  State<_ScriptRow> createState() => _ScriptRowState();
}

class _ScriptRowState extends State<_ScriptRow> {
  bool _hovered = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final showActions = _hovered || _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: showActions ? context.colors.chip : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Text(
                '⌘',
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.script.name}: ${widget.script.command.replaceAll('\n', ' ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              AnimatedOpacity(
                opacity: showActions ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !showActions,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TerminalToolButton(
                        icon: Icons.play_arrow_outlined,
                        label: dt(context, 'run'),
                        showLabel: false,
                        onPressed: widget.onRun,
                      ),
                      if (widget.onEdit != null)
                        TerminalToolButton(
                          icon: Icons.edit_outlined,
                          label: dt(context, 'editScript'),
                          showLabel: false,
                          onPressed: widget.onEdit,
                        ),
                      TerminalToolButton(
                        icon: Icons.arrow_forward,
                        label: dt(context, 'toEditor'),
                        showLabel: false,
                        onPressed: widget.onToEditor,
                      ),
                    ],
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

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 7) {
        canvas.drawPath(metric.extractPath(offset, offset + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => color != oldDelegate.color;
}

Future<void> editDesktopTerminalScript(
  BuildContext context, {
  ScriptModel? script,
  String? command,
  String? group,
  bool base64 = false,
}) => showAppDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ScriptDialog(
    script: script,
    command: command,
    group: group,
    base64: base64,
  ),
);

class _ScriptDialog extends ConsumerStatefulWidget {
  const _ScriptDialog({
    this.script,
    this.command,
    this.group,
    this.base64 = false,
  });
  final ScriptModel? script;
  final String? command, group;
  final bool base64;
  @override
  ConsumerState<_ScriptDialog> createState() => _ScriptDialogState();
}

class _ScriptDialogState extends ConsumerState<_ScriptDialog> {
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
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _command.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups =
        ref.watch(desktopTerminalScriptCatalogProvider).valueOrNull?.groups ??
        [];
    Widget field(
      String label,
      TextEditingController controller, {
      int lines = 1,
      bool required = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 7),
          TextFormField(
            controller: controller,
            maxLines: lines,
            enabled: !_saving,
            style: TextStyle(
              fontSize: 13,
              fontFamily: lines > 1 ? 'monospace' : null,
            ),
            validator: required
                ? (v) => v == null || v.trim().isEmpty
                      ? dt(context, 'required')
                      : null
                : null,
            decoration: desktopInputDecoration(context),
          ),
        ],
      ),
    );
    return DesktopManagementDialog(
      title: dt(context, widget.script == null ? 'newScript' : 'editScript'),
      busy: _saving,
      width: 750,
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(dt(context, 'scriptName'), _name, required: true),
            field(dt(context, 'description'), _description),
            DesktopSelect(
              options: {
                for (final g in groups)
                  if (g.id != 'builtin') g.id: g.name,
              },
              values: [_group],
              onSelected: (v) => setState(() => _group = v),
              enabled: !_saving,
            ),
            const SizedBox(height: 14),
            field(dt(context, 'command'), _command, lines: 9, required: true),
            CheckboxListTile(
              value: _base64,
              onChanged: _saving ? null : (v) => setState(() => _base64 = v!),
              title: const Text('Base64'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: context.colors.danger)),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(dt(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(dt(context, 'save')),
        ),
      ],
    );
  }
}

class _ScriptGroupsDialog extends ConsumerWidget {
  const _ScriptGroupsDialog();
  Future<void> _mutate(
    BuildContext context,
    WidgetRef ref, {
    String? id,
    String name = '',
  }) async {
    final value = await terminalTextPrompt(
      context,
      title: dt(context, 'groups'),
      value: name,
    );
    if (value == null || !context.mounted) return;
    try {
      final form = ScriptGroupFormData(id: id, name: value);
      final repo = ref.read(scriptRepositoryProvider);
      if (id == null) {
        await repo.createGroup(form);
      } else {
        await repo.updateGroup(form);
      }
      ref.invalidate(desktopTerminalScriptCatalogProvider);
    } catch (e) {
      if (context.mounted) terminalNotice(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups =
        ref.watch(desktopTerminalScriptCatalogProvider).valueOrNull?.groups ??
        [];
    return DesktopManagementDialog(
      title: dt(context, 'groups'),
      body: Column(
        children: [
          for (final group in groups)
            ListTile(
              dense: true,
              title: Text(group.name),
              trailing: group.id == 'default' || group.id == 'builtin'
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _mutate(
                            context,
                            ref,
                            id: group.id,
                            name: group.name,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                        ),
                        IconButton(
                          onPressed: () async {
                            final confirm = await showAppDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(dt(context, 'deleteGroup')),
                                content: Text(group.name),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(dt(context, 'cancel')),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(dt(context, 'delete')),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true || !context.mounted) return;
                            try {
                              await ref
                                  .read(scriptRepositoryProvider)
                                  .deleteGroup(group.id);
                              ref.invalidate(
                                desktopTerminalScriptCatalogProvider,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                terminalNotice(context, e.toString());
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                        ),
                      ],
                    ),
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => _mutate(context, ref),
          child: Text(dt(context, 'addGroup')),
        ),
      ],
    );
  }
}
