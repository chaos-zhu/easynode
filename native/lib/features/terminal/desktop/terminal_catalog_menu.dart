import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/app_color_theme.dart';
import 'terminal_widgets.dart';

class TerminalCatalogEntry<T> {
  const TerminalCatalogEntry({
    required this.id,
    required this.label,
    this.value,
    this.children = const [],
  });
  final String id, label;
  final T? value;
  final List<TerminalCatalogEntry<T>> children;
}

/// Web's flat dropdown and two-column, hover-driven cascader share their rows.
class TerminalCatalogMenu<T> extends StatefulWidget {
  const TerminalCatalogMenu({
    super.key,
    required this.entries,
    required this.onSelected,
  });
  final List<TerminalCatalogEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  State<TerminalCatalogMenu<T>> createState() => _TerminalCatalogMenuState<T>();
}

class _TerminalCatalogMenuState<T> extends State<TerminalCatalogMenu<T>> {
  int? _activeGroup;

  double _columnWidth(List<TerminalCatalogEntry<T>> entries, bool grouped) {
    var width = grouped ? 180.0 : 120.0;
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(
          text: entry.label,
          style: TextStyle(
            fontSize: 14,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            fontWeight: grouped ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width = math.max(width, painter.width + (grouped ? 64 : 32));
      painter.dispose();
    }
    return width.clamp(grouped ? 180 : 120, 300);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final grouped = entries.any((entry) => entry.children.isNotEmpty);
    final children = _activeGroup != null && _activeGroup! < entries.length
        ? entries[_activeGroup!].children
        : <TerminalCatalogEntry<T>>[];
    final leftWidth = _columnWidth(entries, grouped);
    final rightWidth = children.isEmpty ? 0.0 : _columnWidth(children, true);
    final rowHeight = math.max(
      grouped ? 34.0 : 32.0,
      MediaQuery.textScalerOf(context).scale(14) * 1.5 + 10,
    );
    final height = grouped ? 204.0 : entries.length * rowHeight + 10;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SizedBox(
        width: leftWidth + rightWidth,
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: leftWidth.round(),
              child: ListView(
                key: const Key('terminal-catalog-root'),
                padding: EdgeInsets.symmetric(vertical: grouped ? 6 : 5),
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _row(
                      entries[i],
                      rowHeight,
                      grouped: grouped,
                      active: _activeGroup == i,
                      onExpand: () => setState(() => _activeGroup = i),
                    ),
                ],
              ),
            ),
            if (children.isNotEmpty) ...[
              VerticalDivider(width: 1, color: context.colors.border),
              Expanded(
                flex: rightWidth.round(),
                child: ListView(
                  key: ValueKey('terminal-catalog-children-$_activeGroup'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final entry in children)
                      _row(entry, rowHeight, grouped: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    TerminalCatalogEntry<T> entry,
    double height, {
    required bool grouped,
    bool active = false,
    VoidCallback? onExpand,
  }) {
    final branch = entry.children.isNotEmpty;
    void select() {
      if (branch) {
        onExpand?.call();
      } else if (entry.value != null) {
        widget.onSelected(entry.value as T);
      }
    }

    return MouseRegion(
      onEnter: branch ? (_) => onExpand?.call() : null,
      child: TextButton(
        key: ValueKey('terminal-catalog-${entry.id}'),
        onPressed: select,
        onFocusChange: branch
            ? (focused) {
                if (focused) onExpand?.call();
              }
            : null,
        style:
            TextButton.styleFrom(
              minimumSize: Size(0, height),
              padding: EdgeInsets.only(
                left: grouped ? 28 : 16,
                right: grouped ? 18 : 16,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
              shape: const RoundedRectangleBorder(),
              alignment: Alignment.centerLeft,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    active || !grouped && states.contains(WidgetState.hovered)
                    ? context.colors.accent
                    : context.colors.text,
              ),
              overlayColor: WidgetStatePropertyAll(
                grouped
                    ? context.colors.chip
                    : context.colors.accent.withValues(alpha: .1),
              ),
            ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (branch) ...[
              const SizedBox(width: 8),
              const TerminalIcon(Icons.arrow_forward, size: 12),
            ],
          ],
        ),
      ),
    );
  }
}
