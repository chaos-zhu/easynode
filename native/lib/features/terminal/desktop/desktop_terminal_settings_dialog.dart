import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../../core/ui/desktop_select.dart';
import 'desktop_terminal_settings.dart';
import 'terminal_output_highlighter.dart';
import 'terminal_widgets.dart';

part 'desktop_terminal_theme_editor.dart';
part 'desktop_terminal_rule_editor.dart';

final desktopTerminalImagePreviewProvider = StateProvider<Uint8List?>(
  (ref) => null,
);

Future<void> showDesktopTerminalSettings(BuildContext context) =>
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DesktopTerminalSettingsDialog(),
    );

class DesktopTerminalSettingsDialog extends ConsumerStatefulWidget {
  const DesktopTerminalSettingsDialog({super.key});
  @override
  ConsumerState<DesktopTerminalSettingsDialog> createState() =>
      _DesktopTerminalSettingsDialogState();
}

class _DesktopTerminalSettingsDialogState
    extends ConsumerState<DesktopTerminalSettingsDialog> {
  DesktopTerminalSettings? _draft;
  int _section = 0;
  final _form = GlobalKey<FormState>();
  String _search = '';
  String? _error;
  bool _saving = false;
  Uint8List? _image;
  String _imageName = '';
  final _sample = TextEditingController(
    text:
        'user@server:~\$ systemctl status nginx\r\nINFO connected 192.168.1.10:22\r\nWARNING slow response 230ms\r\nERROR permission denied /var/log/nginx\r\nSuccess: service running\r\n',
  );
  late final StateController<DesktopTerminalSettings?> _preview;
  late final StateController<Uint8List?> _imagePreview;
  @override
  void initState() {
    super.initState();
    _preview = ref.read(desktopTerminalPreviewProvider.notifier);
    _imagePreview = ref.read(desktopTerminalImagePreviewProvider.notifier);
  }

  @override
  void dispose() {
    _sample.dispose();
    // The preview state belongs to this route; leaving it restores saved values.
    Future.microtask(() {
      if (_preview.mounted) _preview.state = null;
      if (_imagePreview.mounted) _imagePreview.state = null;
    });
    super.dispose();
  }

  void _change(VoidCallback mutation) {
    setState(mutation);
    _preview.state = _draft!.copy();
  }

  Future<void> _save() async {
    if (_saving ||
        _draft == null ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final chooseImageMessage = dt(context, 'chooseImage');
    try {
      if (_draft!.background['mode'] == 'image' && _image != null) {
        _draft!.background['assetId'] = await ref
            .read(desktopTerminalSettingsRepositoryProvider)
            .upload(_image!, _imageName);
      }
      if (_draft!.background['mode'] == 'image' &&
          _draft!.background['assetId'] == null) {
        throw FormatException(chooseImageMessage);
      }
      await ref.read(desktopTerminalSettingsProvider.notifier).save(_draft!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final imageLimitMessage = dt(context, 'imageLimit');
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final data =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (data == null || data.isEmpty || data.length > 5 * 1024 * 1024) {
        throw FormatException(imageLimitMessage);
      }
      final codec = await ui.instantiateImageCodec(data);
      codec.dispose();
      if (!mounted) return;
      _imagePreview.state = data;
      _change(() {
        _image = data;
        _imageName = file.name;
        _draft!.background['mode'] = 'image';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Map<String, String> _themeOptions(Map<String, dynamic> themes) => {
    for (final name in themes.keys) 'builtin:$name': name,
    for (final theme in _draft!.appearance['customThemes'] as List)
      theme['id'] as String: theme['name'] as String,
  };
  void _selectTheme(String id) => _change(() {
    _draft!.appearance['activeThemeId'] = id;
    _draft!.background['mode'] = 'theme';
  });
  Future<void> _editTheme(Map<String, dynamic>? theme) async {
    final colors = resolvedTerminalColors(
      _draft!,
      ref.read(desktopTerminalThemesProvider).valueOrNull ?? {},
    );
    final edited = await showAppDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ThemeEditor(
        theme:
            theme ??
            {'id': 'custom:${const Uuid().v4()}', 'name': '', 'colors': colors},
      ),
    );
    if (!mounted || edited == null) return;
    final custom = _draft!.appearance['customThemes'] as List;
    if (custom.any(
      (item) =>
          item['id'] != edited['id'] &&
          item['name'].toString().toLowerCase() ==
              edited['name'].toString().toLowerCase(),
    )) {
      setState(() => _error = dt(context, 'duplicateName'));
      return;
    }
    _change(() {
      custom.removeWhere((item) => item['id'] == edited['id']);
      custom.add(edited);
      _draft!.appearance['activeThemeId'] = edited['id'];
      _draft!.background['mode'] = 'theme';
    });
  }

  List<Map<String, dynamic>> _rules(List<Map<String, dynamic>> builtin) {
    final overrides = {
      for (final r in _draft!.highlighting['builtinOverrides'] as List)
        r['id']: terminalMap(r),
    };
    return [
      ...builtin.map((r) => overrides[r['id']] ?? r),
      ...(_draft!.highlighting['customRules'] as List).map(terminalMap),
    ];
  }

  void _storeRule(
    Map<String, dynamic> rule,
    List<Map<String, dynamic>> builtins,
  ) {
    _change(() {
      final key = builtins.any((r) => r['id'] == rule['id'])
          ? 'builtinOverrides'
          : 'customRules';
      final list = _draft!.highlighting[key] as List;
      list.removeWhere((r) => r['id'] == rule['id']);
      list.add(rule);
    });
  }

  Future<void> _editRule(
    Map<String, dynamic>? rule,
    List<Map<String, dynamic>> builtins,
  ) async {
    final data =
        rule ??
        {
          'id': const Uuid().v4(),
          'title': '',
          'pattern': '',
          'flags': 'gi',
          'scope': 'match',
          'priority': 0,
          'enabled': true,
          'style': {
            'foreground': {'source': 'theme', 'token': 'cyan'},
            'background': null,
            'bold': false,
            'italic': false,
            'underline': false,
          },
        };
    final edited = await showAppDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RuleEditor(rule: data),
    );
    if (!mounted || edited == null) return;
    _storeRule(edited, builtins);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(desktopTerminalSettingsProvider);
    _draft ??= loaded.valueOrNull?.copy();
    final themes = ref.watch(desktopTerminalThemesProvider).valueOrNull ?? {};
    final builtins = ref.watch(desktopHighlightRulesProvider).valueOrNull ?? [];
    return DesktopManagementDialog(
      title: dt(context, 'settings'),
      width: 1160,
      busy: _saving,
      body: Form(
        key: _form,
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height * .70).clamp(300, 700),
          child: _draft == null
              ? loaded.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(desktopTerminalSettingsProvider),
                      child: Text('${dt(context, 'retry')}: $e'),
                    ),
                  ),
                  data: (_) => const SizedBox.shrink(),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 148,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.colors.canvas.withValues(alpha: .35),
                        border: Border.all(
                          color: context.colors.border.withValues(alpha: .65),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in [
                            'appearance',
                            'highlighting',
                            'behavior',
                            'menu',
                          ].indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SizedBox(
                                height: 42,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    foregroundColor: _section == item.$1
                                        ? context.colors.accent
                                        : context.colors.text,
                                    backgroundColor: _section == item.$1
                                        ? context.colors.accentSoft
                                        : Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    splashFactory: NoSplash.splashFactory,
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () =>
                                            setState(() => _section = item.$1),
                                  child: Text(dt(context, item.$2)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _saving,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                dt(context, 'previewHint'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.muted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              switch (_section) {
                                0 => _appearance(themes),
                                1 => _highlighting(themes, builtins),
                                2 => _behavior(),
                                _ => _menu(),
                              },
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: context.colors.danger,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(dt(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _saving || _draft == null ? null : _save,
          child: Text(dt(context, 'save')),
        ),
      ],
    );
  }

  Widget _title(String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      dt(context, key),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
  Widget _appearance(Map<String, dynamic> themes) {
    final draft = _draft!;
    final custom = (draft.appearance['customThemes'] as List)
        .map(terminalMap)
        .toList();
    final options = _themeOptions(themes);
    final filtered = options.entries.where(
      (e) => e.value.toLowerCase().contains(_search.toLowerCase()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _title('themeLibrary')),
            OutlinedButton(
              onPressed: custom.length >= 50 ? null : () => _editTheme(null),
              child: Text(dt(context, 'newTheme')),
            ),
          ],
        ),
        TextField(
          decoration: desktopInputDecoration(
            context,
            hint: dt(context, 'searchTheme'),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 230),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in filtered)
                  SizedBox(
                    width: 186,
                    child: Material(
                      color: context.colors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: draft.themeId == option.key
                              ? context.colors.accent
                              : context.colors.border,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _selectTheme(option.key),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Builder(
                                builder: (context) {
                                  final preview = draft.copy();
                                  preview.appearance['activeThemeId'] =
                                      option.key;
                                  final colors = resolvedTerminalColors(
                                    preview,
                                    themes,
                                  );
                                  return Container(
                                    height: 43,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.all(8),
                                    color: terminalColor(
                                      colors['background'],
                                      Colors.black,
                                    ),
                                    child: Text(
                                      'user@server:~\$',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: terminalColor(
                                          colors['foreground'],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                option.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (option.key.startsWith('custom:'))
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _editTheme(
                                        custom.firstWhere(
                                          (t) => t['id'] == option.key,
                                        ),
                                      ),
                                      child: Text(
                                        dt(context, 'edit'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _change(() {
                                        (draft.appearance['customThemes']
                                                as List)
                                            .removeWhere(
                                              (t) => t['id'] == option.key,
                                            );
                                        if (draft.themeId == option.key) {
                                          draft.appearance['activeThemeId'] =
                                              'builtin:Cobalt_Neon';
                                        }
                                      }),
                                      child: Text(
                                        dt(context, 'delete'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _title('font'),
        Row(
          children: [
            Expanded(
              child: DesktopSelect(
                options: const {
                  'monospace': 'Monospace',
                  'Menlo': 'Menlo',
                  'Monaco': 'Monaco',
                  'Consolas': 'Consolas',
                  'Courier New': 'Courier New',
                  'Cascadia Code': 'Cascadia Code',
                  'JetBrains Mono': 'JetBrains Mono',
                },
                values: [draft.fontFamily],
                onSelected: (v) => _change(() => draft.font['family'] = v),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: TextFormField(
                initialValue: '${draft.fontSize.round()}',
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: desktopInputDecoration(context, hint: '6–30'),
                onChanged: (v) {
                  final size = int.tryParse(v);
                  if (size != null) {
                    _change(() => draft.font['size'] = size.clamp(6, 30));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final key in ['foreground', 'cursor', 'selectionBackground'])
              SizedBox(
                width: 195,
                child: TextFormField(
                  initialValue: draft.overrides[key]?.toString() ?? '',
                  decoration: desktopInputDecoration(
                    context,
                    hint: dt(context, key),
                  ),
                  validator: (value) =>
                      value != null && value.isNotEmpty && !_validColor(value)
                      ? dt(context, 'invalidColor')
                      : null,
                  onChanged: (v) {
                    if (v.isEmpty || _validColor(v)) {
                      _change(
                        () => draft.overrides[key] = v.isEmpty ? null : v,
                      );
                    }
                  },
                ),
              ),
          ],
        ),
        _title('background'),
        DesktopSelect(
          options: {
            'theme': dt(context, 'themeBackground'),
            'image': dt(context, 'imageBackground'),
            if (draft.background['mode'] == 'html')
              'html': dt(context, 'htmlBackgroundDeferred'),
          },
          values: [draft.background['mode'] as String],
          onSelected: (v) {
            if (v == 'image' &&
                draft.background['assetId'] == null &&
                _image == null) {
              _pickImage();
            } else {
              _change(() => draft.background['mode'] = v);
            }
          },
        ),
        if (draft.background['mode'] == 'image') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined, size: 17),
            label: Text(
              _imageName.isEmpty ? dt(context, 'chooseImage') : _imageName,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DesktopSelect(
                  options: {
                    'cover': dt(context, 'cover'),
                    'contain': dt(context, 'contain'),
                    'fill': dt(context, 'fill'),
                  },
                  values: [draft.background['fit'] as String],
                  onSelected: (v) => _change(() => draft.background['fit'] = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DesktopSelect(
                  options: {
                    'center': dt(context, 'center'),
                    'top': dt(context, 'top'),
                    'bottom': dt(context, 'bottom'),
                    'left': dt(context, 'left'),
                    'right': dt(context, 'right'),
                  },
                  values: [draft.background['position'] as String],
                  onSelected: (v) =>
                      _change(() => draft.background['position'] = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DesktopSelect(
            options: {
              'auto': dt(context, 'autoOverlay'),
              'dark': dt(context, 'darkOverlay'),
              'light': dt(context, 'lightOverlay'),
            },
            values: [draft.background['overlay']['tone'] as String],
            onSelected: (v) =>
                _change(() => draft.background['overlay']['tone'] = v),
          ),
          Slider(
            value: (draft.background['overlay']['opacity'] as num).toDouble(),
            min: 0,
            max: 1,
            label:
                '${((draft.background['overlay']['opacity'] as num) * 100).round()}%',
            onChanged: (v) =>
                _change(() => draft.background['overlay']['opacity'] = v),
          ),
        ],
        const SizedBox(height: 16),
        _terminalPreview(
          themes,
          ref.read(desktopHighlightRulesProvider).valueOrNull ?? [],
        ),
      ],
    );
  }

  Widget _terminalPreview(
    Map<String, dynamic> themes,
    List<Map<String, dynamic>> builtins,
  ) {
    final highlighter = TerminalOutputHighlighter()
      ..configure(_draft!, builtins);
    final terminal = Terminal()..write(highlighter.process(_sample.text));
    return SizedBox(
      height: 150,
      child: TerminalView(
        terminal,
        readOnly: true,
        theme: desktopTerminalTheme(_draft!, themes),
        textStyle: TerminalStyle(
          fontSize: _draft!.fontSize,
          fontFamily: _draft!.fontFamily,
        ),
        padding: const EdgeInsets.all(10),
      ),
    );
  }

  Widget _highlighting(
    Map<String, dynamic> themes,
    List<Map<String, dynamic>> builtin,
  ) {
    final draft = _draft!;
    final rules = _rules(builtin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: draft.highlighting['enabled'] == true,
          onChanged: (v) => _change(() => draft.highlighting['enabled'] = v),
          title: Text(dt(context, 'enableHighlight')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: draft.highlighting['debugMode'] == true,
          onChanged: (v) => _change(() => draft.highlighting['debugMode'] = v),
          title: Text(dt(context, 'debugHighlight')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        Row(
          children: [
            Expanded(child: _title('highlightRules')),
            OutlinedButton(
              onPressed: rules.length >= 50
                  ? null
                  : () => _editRule(null, builtin),
              child: Text(dt(context, 'newRule')),
            ),
          ],
        ),
        for (final rule in rules)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(
              value: rule['enabled'] == true,
              onChanged: (v) {
                final updated = cloneTerminalJson(rule);
                updated['enabled'] = v;
                _storeRule(updated, builtin);
              },
            ),
            title: Text(
              rule['title'] as String,
              style: const TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              rule['pattern'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _editRule(rule, builtin),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
                IconButton(
                  onPressed: () => _change(() {
                    final isBuiltin = builtin.any((r) => r['id'] == rule['id']);
                    (draft.highlighting[isBuiltin
                                ? 'builtinOverrides'
                                : 'customRules']
                            as List)
                        .removeWhere((r) => r['id'] == rule['id']);
                  }),
                  tooltip: dt(
                    context,
                    builtin.any((r) => r['id'] == rule['id'])
                        ? 'reset'
                        : 'delete',
                  ),
                  icon: Icon(
                    builtin.any((r) => r['id'] == rule['id'])
                        ? Icons.restore
                        : Icons.delete_outline,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        _title('preview'),
        TextField(
          controller: _sample,
          maxLines: 3,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: desktopInputDecoration(context),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        _terminalPreview(themes, builtin),
      ],
    );
  }

  Widget _behavior() => Column(
    children: [
      for (final key in [
        'autoReconnect',
        'autoExecuteScript',
        'autoShowContextMenu',
        'statusBarEnabled',
      ])
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(dt(context, key), style: const TextStyle(fontSize: 13)),
          value: _draft!.behavior[key] == true,
          onChanged: (v) => _change(() => _draft!.behavior[key] = v),
        ),
    ],
  );
  Widget _menu() {
    final preferences = ref.watch(desktopTerminalPreferencesProvider);
    return Column(
      children: [
        for (final key in [
          'hostGroupCascader',
          'scriptLibraryCascader',
          'scriptLibrary',
        ])
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(dt(context, key), style: const TextStyle(fontSize: 13)),
            value: preferences[key] as bool? ?? key == 'scriptLibrary',
            onChanged: (v) async {
              try {
                await ref
                    .read(desktopTerminalPreferencesProvider.notifier)
                    .set(key, v);
              } catch (e) {
                if (mounted) setState(() => _error = e.toString());
              }
            },
          ),
      ],
    );
  }
}

bool _validColor(String value) => RegExp(
  r'^(?:#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})|rgba?\(\s*[\d.]+%?\s*,\s*[\d.]+%?\s*,\s*[\d.]+%?(?:\s*,\s*[\d.]+%?)?\s*\)|transparent)$',
  caseSensitive: false,
).hasMatch(value);
