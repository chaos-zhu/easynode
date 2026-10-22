import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/desktop_form_controls.dart';
import '../../../core/ui/desktop_management_dialog.dart';
import '../../shell/editor/editor_language.dart';
import '../../shell/sftp_session_manager.dart';
import 'desktop_code_editor.dart';
import 'desktop_terminal_settings.dart';
import 'desktop_text_codec.dart';
import 'terminal_widgets.dart';

class DesktopSftpEditor extends ConsumerStatefulWidget {
  const DesktopSftpEditor({
    super.key,
    required this.manager,
    required this.remotePath,
    required this.fileName,
  });
  final SftpSessionManager manager;
  final String remotePath, fileName;
  @override
  ConsumerState<DesktopSftpEditor> createState() => _DesktopSftpEditorState();
}

class _DesktopSftpEditorState extends ConsumerState<DesktopSftpEditor> {
  CodeLineEditingController? _code;
  DesktopTextCodec? _codec;
  Uint8List? _bytes;
  String _original = '',
      _encoding = 'auto',
      _detectedEncoding = 'utf8',
      _eol = 'LF',
      _savedEol = 'LF';
  late String _language;
  String? _theme, _error;
  bool _saving = false, _loading = true, _allowClose = false, _wasDirty = false;
  bool get _dirty =>
      _code != null && (_code!.text != _original || _eol != _savedEol);
  static const _languages = {
    'plaintext': 'Plain Text',
    'json': 'JSON',
    'vue': 'Vue',
    'typescript': 'TypeScript',
    'lua': 'Lua',
    'markdown': 'Markdown',
    'yaml': 'YAML',
    'xml': 'XML',
    'php': 'PHP',
    'sql': 'SQL',
    'go': 'Go',
    'html': 'HTML',
    'javascript': 'JavaScript',
    'java': 'Java',
    'kotlin': 'Kotlin',
    'python': 'Python',
    'redis': 'Redis',
    'shell': 'Shell',
    'css': 'CSS',
    'ini': 'INI',
    'dockerfile': 'Dockerfile',
    'nginx': 'Nginx',
    'dart': 'Dart',
  };
  @override
  void initState() {
    super.initState();
    var detected = detectFromFileName(widget.fileName).id.toLowerCase();
    if (detected == 'bash') detected = 'shell';
    _language = _languages.containsKey(detected) ? detected : 'plaintext';
    final ext = widget.fileName.split('.').last.toLowerCase();
    if (_languages.containsKey(ext)) _language = ext;
    _load();
  }

  @override
  void dispose() {
    _code?.dispose();
    super.dispose();
  }

  void _changed() {
    final dirty = _dirty;
    if (mounted && dirty != _wasDirty) setState(() => _wasDirty = dirty);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.manager.readTextFile(widget.remotePath);
      final codec = await DesktopTextCodec.load();
      if (!mounted) return;
      _codec = codec;
      _decode(bytes, _encoding);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _decode(Uint8List bytes, String requestedEncoding) {
    var encoding = requestedEncoding;
    if (encoding == 'auto') {
      try {
        utf8.decode(bytes);
        encoding = 'utf8';
      } on FormatException {
        encoding = 'gb18030';
      }
    }
    final text = _codec!.decode(bytes, encoding);
    _bytes = bytes;
    _encoding = requestedEncoding;
    _detectedEncoding = encoding;
    _eol = detectTextEol(text);
    _savedEol = _eol;
    _code?.dispose();
    _code = CodeLineEditingController.fromText(normalizeTextEol(text))
      ..addListener(_changed);
    _original = _code!.text;
    setState(() {
      _loading = false;
      _error = null;
    });
  }

  Future<bool> _confirm(String key) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (context) => DesktopManagementDialog(
          title: dt(context, 'editor.$key'),
          width: 460,
          body: Text(dt(context, 'editor.${key}Body')),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dt(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(dt(context, 'confirm')),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _changeEncoding(String encoding) async {
    if (encoding == _encoding || _saving) return;
    if (_dirty && !await _confirm('reload')) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.manager.readTextFile(widget.remotePath);
      if (!mounted) return;
      _decode(bytes, encoding);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<bool> _save() async {
    if (_saving || _code == null) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final content = _code!.text, eol = _eol;
      var bytes = _codec!.encode(applyTextEol(content, eol), _detectedEncoding);
      if (_detectedEncoding == 'utf8' &&
          _bytes!.length >= 3 &&
          _bytes![0] == 0xef &&
          _bytes![1] == 0xbb &&
          _bytes![2] == 0xbf) {
        bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, ...bytes]);
      }
      await widget.manager.writeFileBytes(widget.remotePath, bytes);
      if (!mounted) return false;
      setState(() {
        _original = content;
        _savedEol = eol;
        _bytes = bytes;
      });
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final action = await showAppDialog<String>(
        context: context,
        builder: (context) => DesktopManagementDialog(
          title: dt(context, 'editor.unsaved'),
          width: 500,
          body: Text(dt(context, 'editor.unsavedBody')),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dt(context, 'cancel')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(dt(context, 'editor.discard')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: Text(dt(context, 'editor.saveClose')),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'save' && !await _save()) return;
    }
    if (!mounted) return;
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _reset() async {
    if (!await _confirm('reset') || !mounted) return;
    _code!.text = _original;
    setState(() => _eol = _savedEol);
  }

  void _preference(String key, Object value) => ref
      .read(desktopTerminalPreferencesProvider.notifier)
      .set('editor$key', value);
  @override
  Widget build(BuildContext context) {
    _wasDirty = _dirty;
    final pref = ref.watch(desktopTerminalPreferencesProvider);
    final wrap = pref['editorWrap'] != false,
        minimap = pref['editorMinimap'] != false;
    final font = (pref['editorFont'] as num?)?.toDouble() ?? 14;
    final mapSize = pref['editorMinimapSize'] as String? ?? 'medium';
    final theme =
        _theme ??
        (Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light');
    final mode =
        builtinAllLanguages[_language == 'shell'
            ? 'bash'
            : _language == 'vue' || _language == 'html'
            ? 'xml'
            : _language];
    return PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (_dirty) _save();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (_dirty) _save();
          },
        },
        child: Dialog(
          alignment: Alignment.topCenter,
          insetPadding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: MediaQuery.sizeOf(context).height * .03,
          ),
          backgroundColor: context.colors.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width * .68,
            height: MediaQuery.sizeOf(context).height * .88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${dt(context, 'editor.title')} - ${widget.remotePath}${_dirty ? ' [${dt(context, 'editor.changed')}]' : ''} - ${desktopEditorSize(_bytes?.length ?? 0)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      TerminalToolButton(
                        icon: Icons.close,
                        label: dt(context, 'close'),
                        showLabel: false,
                        onPressed: _saving ? null : _close,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      EditorChoice(
                        label: dt(context, 'editor.theme'),
                        value: theme,
                        options: {
                          'contrast': dt(context, 'editor.contrast'),
                          'dark': dt(context, 'editor.dark'),
                          'light': dt(context, 'editor.light'),
                        },
                        onChanged: (v) => setState(() => _theme = v),
                      ),
                      EditorChoice(
                        label: dt(context, 'editor.language'),
                        value: _language,
                        options: _languages,
                        onChanged: (v) => setState(() => _language = v),
                      ),
                      EditorChoice(
                        label: dt(context, 'editor.eol'),
                        value: _eol,
                        options: const {
                          'LF': 'LF (Linux)',
                          'CRLF': 'CRLF (Windows)',
                          'CR': 'CR (Mac)',
                        },
                        enabled: !_saving,
                        onChanged: (v) => setState(() => _eol = v),
                      ),
                      EditorChoice(
                        label: dt(context, 'editor.encoding'),
                        value: _encoding,
                        options: {
                          'auto':
                              '${dt(context, 'editor.auto')} (${_detectedEncoding == 'utf8' ? 'UTF-8' : 'GB18030'})',
                          'utf8': 'UTF-8',
                          'gb18030': 'GB18030',
                        },
                        enabled: !_loading && !_saving,
                        onChanged: _changeEncoding,
                      ),
                      EditorSwitch(
                        label: dt(context, 'editor.wrap'),
                        value: wrap,
                        onChanged: (v) => _preference('Wrap', v),
                      ),
                      EditorSwitch(
                        label: dt(context, 'editor.minimap'),
                        value: minimap,
                        onChanged: (v) => _preference('Minimap', v),
                      ),
                      if (minimap)
                        EditorChoice(
                          label: '',
                          value: mapSize,
                          options: {
                            'small': dt(context, 'editor.small'),
                            'medium': dt(context, 'editor.medium'),
                            'large': dt(context, 'editor.large'),
                          },
                          onChanged: (v) => _preference('MinimapSize', v),
                        ),
                      EditorChoice(
                        label: dt(context, 'editor.font'),
                        value: font.toInt().toString(),
                        options: {
                          for (final n in [12, 14, 16, 18, 20, 22, 24])
                            '$n': '$n',
                        },
                        onChanged: (v) => _preference('Font', int.parse(v)),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: context.colors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (_code == null)
                          TextButton(
                            onPressed: _load,
                            child: Text(dt(context, 'retry')),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _code == null
                      ? const SizedBox.shrink()
                      : AbsorbPointer(
                          absorbing: _saving,
                          child: DesktopCodeEditor(
                            key: ObjectKey(_code),
                            controller: _code!,
                            language: mode == null
                                ? null
                                : CodeHighlightThemeMode(mode: mode),
                            theme: theme,
                            fontSize: font,
                            wordWrap: wrap,
                            minimap: minimap,
                            minimapSize: mapSize,
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: desktopButtonStyle(context),
                        onPressed: _saving ? null : _close,
                        child: Text(dt(context, 'close')),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: desktopButtonStyle(context),
                        onPressed: _dirty && !_saving ? _reset : null,
                        child: Text(dt(context, 'editor.reset')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: desktopButtonStyle(context, primary: true),
                        onPressed: _dirty && !_saving ? _save : null,
                        child: Text(
                          dt(
                            context,
                            _saving ? 'editor.saving' : 'editor.save',
                          ),
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
    );
  }
}
