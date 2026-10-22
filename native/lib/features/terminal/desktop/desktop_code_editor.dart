import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/desktop_popover.dart';
import 'terminal_widgets.dart';

String desktopEditorSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(2)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

/// Compact, non-searchable select shared by editor toolbars.
class EditorChoice extends StatelessWidget {
  const EditorChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      Builder(
        builder: (anchor) => SizedBox(
          height: 26,
          child: OutlinedButton(
            onPressed: !enabled
                ? null
                : () async {
                    final result = await showDesktopPopover<String>(
                      context: anchor,
                      width: 170,
                      maxHeight: 310,
                      builder: (context) => SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final entry in options.entries)
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, entry.key),
                                style: TextButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  foregroundColor: entry.key == value
                                      ? context.colors.accent
                                      : context.colors.text,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  shape: const RoundedRectangleBorder(),
                                ),
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (result != null) onChanged(result);
                  },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 26),
              side: BorderSide(color: context.colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  options[value] ?? value,
                  style: TextStyle(fontSize: 12, color: context.colors.text),
                ),
                const SizedBox(width: 8),
                const TerminalIcon(Icons.keyboard_arrow_down, size: 12),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class EditorSwitch extends StatelessWidget {
  const EditorSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 5),
      SizedBox(
        width: 32,
        height: 24,
        child: FittedBox(
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: context.colors.accent,
          ),
        ),
      ),
    ],
  );
}

/// Native editor surface shared by SFTP editing and the read-only Docker log viewer.
class DesktopCodeEditor extends StatefulWidget {
  const DesktopCodeEditor({
    super.key,
    required this.controller,
    this.language,
    this.theme = 'dark',
    this.fontSize = 14,
    this.wordWrap = true,
    this.minimap = true,
    this.minimapSize = 'medium',
    this.readOnly = false,
    this.follow = false,
  });
  final CodeLineEditingController controller;
  final CodeHighlightThemeMode? language;
  final String theme, minimapSize;
  final double fontSize;
  final bool wordWrap, minimap, readOnly, follow;
  @override
  State<DesktopCodeEditor> createState() => _DesktopCodeEditorState();
}

class _DesktopCodeEditorState extends State<DesktopCodeEditor> {
  final _scroll = CodeScrollController();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updated);
    _updated();
  }

  @override
  void didUpdateWidget(covariant DesktopCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updated);
      widget.controller.addListener(_updated);
    }
    if (widget.follow && !oldWidget.follow) _updated();
  }

  void _updated() {
    if (widget.follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.verticalScroller.hasClients) {
          _scroll.verticalScroller.jumpTo(
            _scroll.verticalScroller.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updated);
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = widget.theme == 'light';
    final background = light
        ? Colors.white
        : widget.theme == 'contrast'
        ? Colors.black
        : const Color(0xff1e1e1e);
    final foreground = light
        ? const Color(0xff333333)
        : const Color(0xffd4d4d4);
    return ColoredBox(
      color: background,
      child: Row(
        children: [
          Expanded(
            child: CodeEditor(
              controller: widget.controller,
              scrollController: _scroll,
              readOnly: widget.readOnly,
              wordWrap: widget.wordWrap,
              padding: const EdgeInsets.symmetric(vertical: 8),
              scrollbarBuilder: (_, child, _) => child,
              style: CodeEditorStyle(
                fontFamily: 'monospace',
                fontSize: widget.fontSize,
                fontHeight: 1.45,
                backgroundColor: background,
                textColor: foreground,
                cursorColor: foreground,
                cursorLineColor: light
                    ? const Color(0xffeeeeee)
                    : const Color(0xff333333),
                codeTheme: CodeHighlightTheme(
                  languages: {
                    if (widget.language != null) 'selected': widget.language!,
                  },
                  theme: light ? vsTheme : vs2015Theme,
                ),
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) =>
                      Row(
                        children: [
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
                          ),
                          DefaultCodeChunkIndicator(
                            width: 14,
                            controller: chunkController,
                            notifier: notifier,
                          ),
                        ],
                      ),
              chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
              findBuilder: (context, controller, readOnly) =>
                  _EditorFind(controller: controller, readOnly: readOnly),
            ),
          ),
          if (widget.minimap)
            SizedBox(
              width: switch (widget.minimapSize) {
                'small' => 65,
                'large' => 140,
                _ => 100,
              },
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.controller,
                    _scroll.verticalScroller,
                  ]),
                  builder: (context, _) => GestureDetector(
                    onTapDown: (details) =>
                        _seek(details.localPosition.dy / constraints.maxHeight),
                    onVerticalDragUpdate: (details) =>
                        _seek(details.localPosition.dy / constraints.maxHeight),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _MinimapPainter(
                          widget.controller.text,
                          foreground,
                          _scroll.verticalScroller,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _seek(double fraction) {
    if (_scroll.verticalScroller.hasClients) {
      _scroll.verticalScroller.jumpTo(
        (fraction * _scroll.verticalScroller.position.maxScrollExtent).clamp(
          0,
          _scroll.verticalScroller.position.maxScrollExtent,
        ),
      );
    }
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.text, this.color, this.scroll);
  final String text;
  final Color color;
  final ScrollController scroll;
  @override
  void paint(Canvas canvas, Size size) {
    final lines = text.split('\n');
    final height = math.min(3.0, size.height / math.max(lines.length, 1));
    final paint = Paint()..color = color.withValues(alpha: .38);
    for (var i = 0; i < lines.length; i++) {
      // Render token runs rather than font glyphs at an unreadable size.
      for (final match in RegExp(r'\S+').allMatches(lines[i])) {
        final x = match.start * .75;
        if (x >= size.width) break;
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            i * height,
            math.min(match.end * .75, size.width) - x,
            math.max(.5, height * .6),
          ),
          paint,
        );
      }
    }
    if (scroll.hasClients) {
      final p = scroll.position;
      final extent = p.maxScrollExtent + p.viewportDimension;
      if (extent > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            size.height * p.pixels / extent,
            size.width,
            size.height * p.viewportDimension / extent,
          ),
          Paint()..color = color.withValues(alpha: .08),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}

class _EditorFind extends StatelessWidget implements PreferredSizeWidget {
  const _EditorFind({required this.controller, required this.readOnly});
  final CodeFindController controller;
  final bool readOnly;
  @override
  Size get preferredSize => Size.fromHeight(
    controller.value == null
        ? 0
        : controller.value!.replaceMode
        ? 76
        : 38,
  );
  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    Widget field(TextEditingController c, FocusNode focus) => Expanded(
      child: TextField(
        controller: c,
        focusNode: focus,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => controller.nextMatch(),
      ),
    );
    Widget button(String text, VoidCallback action) => TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        minimumSize: const Size(28, 30),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
    return Container(
      color: context.colors.card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Column(
        children: [
          Row(
            children: [
              if (!readOnly)
                button(value.replaceMode ? '▾' : '▸', controller.toggleMode),
              field(
                controller.findInputController,
                controller.findInputFocusNode,
              ),
              button(
                'Aa${value.option.caseSensitive ? ' ✓' : ''}',
                controller.toggleCaseSensitive,
              ),
              button(
                '.*${value.option.regex ? ' ✓' : ''}',
                controller.toggleRegex,
              ),
              Text(
                value.result == null
                    ? '0/0'
                    : '${value.result!.index + 1}/${value.result!.matches.length}',
                style: const TextStyle(fontSize: 12),
              ),
              button('↑', controller.previousMatch),
              button('↓', controller.nextMatch),
              button('×', controller.close),
            ],
          ),
          if (value.replaceMode)
            Row(
              children: [
                field(
                  controller.replaceInputController,
                  controller.replaceInputFocusNode,
                ),
                button(dt(context, 'editor.replace'), controller.replaceMatch),
                button(
                  dt(context, 'editor.replaceAll'),
                  controller.replaceAllMatches,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
