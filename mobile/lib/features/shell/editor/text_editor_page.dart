import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../../l10n/app_localizations.dart';
import '../sftp_session_manager.dart';
import 'editor_language.dart';
import 'editor_preferences.dart';
import 'editor_text_sniffer.dart';
import 'text_editor_controller.dart';

class _EditorPalette {
  const _EditorPalette({
    required this.background,
    required this.surface,
    required this.surfaceBorder,
    required this.textColor,
    required this.subtleText,
    required this.gutter,
    required this.gutterActive,
    required this.chip,
    required this.appBarBg,
    required this.appBarFg,
    required this.statusBg,
    required this.actionDivider,
  });

  final Color background;
  final Color surface;
  final Color surfaceBorder;
  final Color textColor;
  final Color subtleText;
  final Color gutter;
  final Color gutterActive;
  final Color chip;
  final Color appBarBg;
  final Color appBarFg;
  final Color statusBg;
  final Color actionDivider;

  static const dark = _EditorPalette(
    background: Color(0xFF0A0F14),
    surface: Color(0xFF111827),
    surfaceBorder: Color(0xFF1F2937),
    textColor: Colors.white,
    subtleText: Color(0xFF9CA3AF),
    gutter: Color(0xFF4B5563),
    gutterActive: Color(0xFF9CA3AF),
    chip: Color(0xFF1F2937),
    appBarBg: Color(0xFF111827),
    appBarFg: Colors.white,
    statusBg: Color(0xFF111827),
    actionDivider: Color(0xFF1F2937),
  );

  static const light = _EditorPalette(
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFF3F4F6),
    surfaceBorder: Color(0xFFE5E7EB),
    textColor: Color(0xFF1F2937),
    subtleText: Color(0xFF6B7280),
    gutter: Color(0xFF9CA3AF),
    gutterActive: Color(0xFF374151),
    chip: Color(0xFFE5E7EB),
    appBarBg: Color(0xFFF9FAFB),
    appBarFg: Color(0xFF111827),
    statusBg: Color(0xFFF3F4F6),
    actionDivider: Color(0xFFE5E7EB),
  );
}

class _SftpManagerWriter implements TextEditorWriter {
  _SftpManagerWriter(this.manager);
  final SftpSessionManager manager;

  @override
  Future<void> writeTextFile(String remotePath, String content) =>
      manager.writeTextFile(remotePath, content);
}

class TextEditorPage extends ConsumerStatefulWidget {
  const TextEditorPage({
    super.key,
    required this.manager,
    required this.remotePath,
    required this.fileName,
  });

  final SftpSessionManager manager;
  final String remotePath;
  final String fileName;

  @override
  ConsumerState<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends ConsumerState<TextEditorPage> {
  late final EditorLanguage _language;
  TextEditorController? _controller;
  bool _loading = true;
  Object? _loadError;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _language = detectFromFileName(widget.fileName);
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.manager.readTextFile(widget.remotePath);
      if (!mounted) return;
      final sniff = sniffAndDecode(bytes);
      final controller = TextEditorController(
        writer: _SftpManagerWriter(widget.manager),
        remotePath: widget.remotePath,
        originalText: sniff.text,
        language: _language,
        totalBytes: bytes.length,
      );
      setState(() {
        _controller = controller;
        _totalBytes = bytes.length;
        _loading = false;
      });
      if (sniff.malformedUtf8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.tr('editor.malformedUtf8'))));
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  _EditorPalette _paletteFor(EditorThemeMode mode) =>
      mode == EditorThemeMode.light ? _EditorPalette.light : _EditorPalette.dark;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(editorPreferencesProvider);
    final palette = _paletteFor(prefs.theme);
    if (_loading) {
      return Scaffold(
        backgroundColor: palette.background,
        appBar: _buildSimpleAppBar(context, palette),
        body: Center(
          child: CircularProgressIndicator(color: palette.subtleText),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: palette.background,
        appBar: _buildSimpleAppBar(context, palette),
        body: _buildErrorState(context, palette, _loadError!),
      );
    }
    final controller = _controller!;
    return PopScope(
      canPop: !controller.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final l = AppLocalizations.of(context);
        final action = await _showDiscardDialog(context);
        if (!context.mounted) return;
        if (action == _DiscardAction.discard) {
          Navigator.of(context).pop();
        } else if (action == _DiscardAction.saveAndLeave) {
          try {
            await controller.save();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.tr('editor.saved'))));
            if (context.mounted) Navigator.of(context).pop();
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.trf('editor.saveFailed', [error.toString()]))),
            );
          }
        }
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          backgroundColor: palette.background,
          appBar: _buildAppBar(context, palette, controller),
          body: Column(
            children: [
              _buildMetaBar(context, palette),
              Expanded(child: _buildEditor(palette, prefs, controller)),
              _buildStatusBar(context, palette, controller),
              SafeArea(top: false, child: _buildActionBar(context, palette, controller)),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSimpleAppBar(BuildContext context, _EditorPalette palette) {
    return AppBar(
      backgroundColor: palette.appBarBg,
      foregroundColor: palette.appBarFg,
      title: _buildTitle(palette),
    );
  }

  Widget _buildTitle(_EditorPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.fileName,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.appBarFg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          widget.remotePath,
          style: TextStyle(fontSize: 11, color: palette.subtleText),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, _EditorPalette palette, Object error) {
    final l = AppLocalizations.of(context);
    String message;
    if (error is SftpFileTooLargeException) {
      message = l.tr('editor.tooLarge');
    } else if (error is SftpBinaryFileException) {
      message = l.tr('editor.binary');
    } else {
      message = l.trf('editor.readFailed', [error.toString()]);
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.subtleText, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.subtleText, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.tr('common.close')),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    _EditorPalette palette,
    TextEditorController controller,
  ) {
    final l = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: palette.appBarBg,
      foregroundColor: palette.appBarFg,
      title: _buildTitle(palette),
      actions: [
        IconButton(
          tooltip: l.tr('editor.undo'),
          icon: const Icon(Icons.undo),
          onPressed: controller.code.canUndo ? controller.code.undo : null,
        ),
        IconButton(
          tooltip: l.tr('editor.redo'),
          icon: const Icon(Icons.redo),
          onPressed: controller.code.canRedo ? controller.code.redo : null,
        ),
        IconButton(
          tooltip: l.tr('editor.settings'),
          icon: const Icon(Icons.tune),
          onPressed: () => _openSettings(context, palette),
        ),
      ],
    );
  }

  Widget _buildMetaBar(BuildContext context, _EditorPalette palette) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: palette.appBarBg,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.chip,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _language.id,
              style: TextStyle(fontSize: 11, color: palette.appBarFg),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l.trf('editor.statusEncoding', [_formatBytes(_totalBytes)]),
            style: TextStyle(fontSize: 11, color: palette.subtleText),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    _EditorPalette palette,
    EditorPreferences prefs,
    TextEditorController controller,
  ) {
    final highlightTheme = prefs.theme == EditorThemeMode.light
        ? atomOneLightTheme
        : atomOneDarkTheme;
    return CodeEditor(
      controller: controller.code,
      wordWrap: prefs.wordWrap,
      style: CodeEditorStyle(
        codeTheme: _language.highlightMode == null
            ? null
            : CodeHighlightTheme(
                languages: {
                  _language.id.toLowerCase():
                      CodeHighlightThemeMode(mode: _language.highlightMode!),
                },
                theme: highlightTheme,
              ),
        backgroundColor: palette.background,
        textColor: palette.textColor,
        fontSize: prefs.fontSize.toDouble(),
        fontFamily: 'monospace',
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
              textStyle: TextStyle(color: palette.gutter, fontSize: 12),
              focusedTextStyle: TextStyle(color: palette.gutterActive, fontSize: 12),
            ),
            DefaultCodeChunkIndicator(
              width: 14,
              controller: chunkController,
              notifier: notifier,
            ),
          ],
        );
      },
      chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    _EditorPalette palette,
    TextEditorController controller,
  ) {
    final l = AppLocalizations.of(context);
    final sel = controller.code.selection;
    final lineIndex = sel.baseIndex;
    final colIndex = sel.baseOffset;
    final total = controller.code.codeLines.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: palette.statusBg,
        border: Border(top: BorderSide(color: palette.surfaceBorder)),
      ),
      child: Row(
        children: [
          Text(
            l.trf('editor.statusPosition', ['${lineIndex + 1}', '${colIndex + 1}']),
            style: TextStyle(fontSize: 11, color: palette.subtleText),
          ),
          const SizedBox(width: 16),
          Text(
            '${_language.id} · ${l.trf('editor.statusSpaces', ['${_language.defaultIndent}'])}',
            style: TextStyle(fontSize: 11, color: palette.subtleText),
          ),
          const Spacer(),
          Text(
            l.trf('editor.statusLineCount', ['${lineIndex + 1}', '$total']),
            style: TextStyle(fontSize: 11, color: palette.subtleText),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Widget _buildActionBar(
    BuildContext context,
    _EditorPalette palette,
    TextEditorController controller,
  ) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.appBarBg,
        border: Border(top: BorderSide(color: palette.actionDivider)),
      ),
      child: Row(
        children: [
          if (controller.isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '• ${l.tr('editor.unsaved')}',
                style: const TextStyle(fontSize: 11, color: Colors.amber),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: Text(l.tr('editor.format')),
            onPressed: controller.canFormat ? () => _onFormat(context, controller) : null,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: controller.saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 16),
            label: Text(l.tr('editor.save')),
            onPressed: (controller.isDirty && !controller.saving)
                ? () => _onSave(context, controller)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _onSave(BuildContext context, TextEditorController controller) async {
    final l = AppLocalizations.of(context);
    try {
      await controller.save();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.saved'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.trf('editor.saveFailed', [error.toString()]))),
      );
    }
  }

  void _onFormat(BuildContext context, TextEditorController controller) {
    final l = AppLocalizations.of(context);
    if (!controller.canFormat) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.formatUnsupported'))));
      return;
    }
    try {
      controller.format();
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.trf('editor.formatFailed', [error.message]))),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.trf('editor.formatFailed', [error.toString()]))),
      );
    }
  }

  Future<void> _openSettings(BuildContext context, _EditorPalette palette) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _EditorSettingsSheet(palette: palette),
    );
  }

  Future<_DiscardAction?> _showDiscardDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<_DiscardAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('editor.discardTitle')),
        content: Text(l.tr('editor.discardBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.keepEditing),
            child: Text(l.tr('editor.discardKeepEditing')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.discard),
            child: Text(l.tr('editor.discardLeave')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.saveAndLeave),
            child: Text(l.tr('editor.discardSaveAndLeave')),
          ),
        ],
      ),
    );
  }
}

class _EditorSettingsSheet extends ConsumerWidget {
  const _EditorSettingsSheet({required this.palette});

  final _EditorPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(editorPreferencesProvider);
    final notifier = ref.read(editorPreferencesProvider.notifier);
    final atMin = prefs.fontSize <= 10;
    final atMax = prefs.fontSize >= 24;

    final labelStyle = TextStyle(
      fontSize: 13,
      color: palette.textColor,
      fontWeight: FontWeight.w600,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.subtleText.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.tr('editor.settings'),
                style: TextStyle(
                  color: palette.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text(l.tr('editor.fontSize'), style: labelStyle)),
                _RoundIconButton(
                  palette: palette,
                  icon: Icons.remove,
                  enabled: !atMin,
                  onTap: atMin ? null : () => notifier.setFontSize(prefs.fontSize - 1),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${prefs.fontSize}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _RoundIconButton(
                  palette: palette,
                  icon: Icons.add,
                  enabled: !atMax,
                  onTap: atMax ? null : () => notifier.setFontSize(prefs.fontSize + 1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l.tr('editor.wordWrap'), style: labelStyle)),
                Switch(
                  value: prefs.wordWrap,
                  onChanged: notifier.setWordWrap,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l.tr('editor.theme'), style: labelStyle)),
                SegmentedButton<EditorThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: EditorThemeMode.dark,
                      label: Text(l.tr('editor.themeDark')),
                      icon: const Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: EditorThemeMode.light,
                      label: Text(l.tr('editor.themeLight')),
                      icon: const Icon(Icons.light_mode_outlined, size: 16),
                    ),
                  ],
                  selected: {prefs.theme},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) notifier.setTheme(set.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.tr('editor.settingsDone')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.palette,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final _EditorPalette palette;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? palette.textColor : palette.subtleText.withValues(alpha: 0.6);
    return Material(
      color: palette.chip,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

enum _DiscardAction { keepEditing, discard, saveAndLeave }
