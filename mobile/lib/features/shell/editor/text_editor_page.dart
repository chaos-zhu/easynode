import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../../l10n/app_localizations.dart';
import '../sftp_session_manager.dart';
import 'editor_language.dart';
import 'text_editor_controller.dart';

class _EditorPalette {
  static const Color background = Color(0xFF0A0F14);
  static const Color statusBg = Color(0xFF111827);
  static const Color statusBorder = Color(0xFF1F2937);
  static const Color statusText = Color(0xFF9CA3AF);
  static const Color gutter = Color(0xFF4B5563);
  static const Color gutterActive = Color(0xFF9CA3AF);
  static const Color appBarBg = Color(0xFF111827);
}

class _SftpManagerWriter implements TextEditorWriter {
  _SftpManagerWriter(this.manager);
  final SftpSessionManager manager;

  @override
  Future<void> writeTextFile(String remotePath, String content) =>
      manager.writeTextFile(remotePath, content);
}

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({
    super.key,
    required this.manager,
    required this.remotePath,
    required this.fileName,
    required this.initialText,
    required this.malformedUtf8,
    required this.totalBytes,
  });

  final SftpSessionManager manager;
  final String remotePath;
  final String fileName;
  final String initialText;
  final bool malformedUtf8;
  final int totalBytes;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final TextEditorController _controller;
  late final EditorLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = detectFromFileName(widget.fileName);
    _controller = TextEditorController(
      writer: _SftpManagerWriter(widget.manager),
      remotePath: widget.remotePath,
      originalText: widget.initialText,
      language: _language,
      totalBytes: widget.totalBytes,
    );
    if (widget.malformedUtf8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.tr('editor.malformedUtf8'))));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_controller.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final action = await _showDiscardDialog(context);
        if (!context.mounted) return;
        if (action == _DiscardAction.discard) {
          Navigator.of(context).pop();
        } else if (action == _DiscardAction.saveAndLeave) {
          try {
            await _controller.save();
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
        animation: _controller,
        builder: (context, _) => Scaffold(
          backgroundColor: _EditorPalette.background,
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              _buildMetaBar(context),
              Expanded(child: _buildEditor()),
              _buildStatusBar(context),
              SafeArea(top: false, child: _buildActionBar(context)),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: _EditorPalette.appBarBg,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.remotePath,
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: l.tr('editor.undo'),
          icon: const Icon(Icons.undo),
          onPressed: _controller.code.canUndo ? _controller.code.undo : null,
        ),
        IconButton(
          tooltip: l.tr('editor.redo'),
          icon: const Icon(Icons.redo),
          onPressed: _controller.code.canRedo ? _controller.code.redo : null,
        ),
      ],
    );
  }

  Widget _buildMetaBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _EditorPalette.appBarBg,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _EditorPalette.statusBorder,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _language.id,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l.trf('editor.statusEncoding', [_formatBytes(widget.totalBytes)]),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return CodeEditor(
      controller: _controller.code,
      style: CodeEditorStyle(
        codeTheme: _language.highlightMode == null
            ? null
            : CodeHighlightTheme(
                languages: {_language.id: CodeHighlightThemeMode(mode: _language.highlightMode!)},
                theme: atomOneDarkTheme,
              ),
        backgroundColor: _EditorPalette.background,
        textColor: Colors.white,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
              textStyle: const TextStyle(color: _EditorPalette.gutter, fontSize: 12),
              focusedTextStyle: const TextStyle(color: _EditorPalette.gutterActive, fontSize: 12),
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

  Widget _buildStatusBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sel = _controller.code.selection;
    final lineIndex = sel.baseIndex;
    final colIndex = sel.baseOffset;
    final total = _controller.code.codeLines.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: _EditorPalette.statusBg,
        border: Border(top: BorderSide(color: _EditorPalette.statusBorder)),
      ),
      child: Row(
        children: [
          Text(
            l.trf('editor.statusPosition', ['${lineIndex + 1}', '${colIndex + 1}']),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
          const SizedBox(width: 16),
          Text(
            '${_language.id} · ${l.trf('editor.statusSpaces', ['${_language.defaultIndent}'])}',
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
          const Spacer(),
          Text(
            l.trf('editor.statusLineCount', ['${lineIndex + 1}', '$total']),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
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

  Widget _buildActionBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _EditorPalette.appBarBg,
        border: Border(top: BorderSide(color: _EditorPalette.statusBorder)),
      ),
      child: Row(
        children: [
          if (_controller.isDirty)
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
            onPressed: _controller.canFormat ? () => _onFormat(context) : null,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _controller.saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 16),
            label: Text(l.tr('editor.save')),
            onPressed:
                (_controller.isDirty && !_controller.saving) ? () => _onSave(context) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _onSave(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      await _controller.save();
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

  void _onFormat(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_controller.canFormat) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.formatUnsupported'))));
      return;
    }
    try {
      _controller.format();
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

enum _DiscardAction { keepEditing, discard, saveAndLeave }
