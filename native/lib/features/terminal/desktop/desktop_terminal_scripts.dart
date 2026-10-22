import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/plus_info_notifier.dart';
import '../../scripts/script_model.dart';
import '../../scripts/script_repository.dart';
import '../../scripts/desktop_script_dialogs.dart';
import '../../../state/desktop_script_catalog_provider.dart';
export '../../../state/desktop_script_catalog_provider.dart'
    show desktopTerminalScriptCatalogProvider;
import 'terminal_widgets.dart';

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
                    builder: (_) => const DesktopScriptGroupsDialog(),
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
  builder: (_) => DesktopScriptDialog(
    script: script,
    command: command,
    group: group,
    base64: base64,
  ),
);
