import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/app_color_theme.dart';
import 'desktop_terminal_status.dart';
import 'desktop_terminal_workspace.dart';
import 'terminal_widgets.dart';

/// Flattens the workspace panes without owning or recreating their SSH sessions.
class DesktopTerminalGrid extends StatefulWidget {
  const DesktopTerminalGrid({
    super.key,
    required this.workspace,
    required this.horizontal,
    required this.showStatusBar,
    required this.paneBuilder,
    required this.onActivate,
    required this.onContextMenu,
    required this.onScripts,
  });
  final DesktopTerminalWorkspace workspace;
  final bool horizontal, showStatusBar;
  final Widget Function(DesktopTerminalTab, DesktopTerminalPane) paneBuilder;
  final void Function(DesktopTerminalTab, DesktopTerminalPane) onActivate;
  final void Function(DesktopTerminalTab, Offset) onContextMenu;
  final void Function(DesktopTerminalTab, DesktopTerminalPane) onScripts;

  @override
  State<DesktopTerminalGrid> createState() => _DesktopTerminalGridState();
}

class _DesktopTerminalGridState extends State<DesktopTerminalGrid> {
  String? _maximizedPane;
  List<double> _gridColumns = [], _gridRows = [];

  Widget _statusDot(DesktopTerminalStatus status) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (status) {
        DesktopTerminalStatus.connected => context.colors.success,
        DesktopTerminalStatus.connecting => context.colors.warning,
        _ => context.colors.danger,
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final manager = widget.workspace;
    final panes = manager.panes;
    if (!panes.any((p) => p.id == _maximizedPane)) _maximizedPane = null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            widget.horizontal && panes.length > 4 && _maximizedPane == null;
        final count = panes.length;
        var cols = count == 1
            ? 1
            : count <= 4
            ? 2
            : math.sqrt(count).ceil();
        var rows = count <= 3 ? 1 : (count / cols).ceil();
        if (count >= 5) {
          // Web limits rows by height, then spreads an incomplete last row.
          final maxRows = math.max(1, (constraints.maxHeight / 250).floor());
          if (rows > maxRows) {
            rows = maxRows;
            cols = (count / rows).ceil();
          }
        }
        if (_gridColumns.length != cols) {
          _gridColumns = List.filled(cols, 1 / cols);
        }
        final splitRows = count == 3 ? 2 : rows;
        if (_gridRows.length != splitRows) {
          _gridRows = List.filled(splitRows, 1 / splitRows);
        }
        final maximized = _maximizedPane != null;
        final width = maximized
            ? constraints.maxWidth
            : horizontal
            ? count * 508.0 - 8
            : math.max(
                constraints.maxWidth,
                cols * 220.0 + (count <= 4 ? (cols - 1) * 8 : 0),
              );
        final height = horizontal || maximized
            ? constraints.maxHeight
            : math.max(
                constraints.maxHeight,
                count == 4 ? 508.0 : rows * 250.0,
              );
        final content = SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (var i = 0; i < panes.length; i++)
                Builder(
                  builder: (context) {
                    final pane = panes[i];
                    final tab = manager.tabs.firstWhere(
                      (t) => t.panes.contains(pane),
                    );
                    final maximized = _maximizedPane == pane.id;
                    final rect = _panelRect(
                      i,
                      count,
                      cols,
                      rows,
                      Size(width, height),
                      horizontal,
                    );
                    return Positioned.fromRect(
                      rect: maximized
                          ? Offset.zero & Size(width, height)
                          : rect,
                      child: Offstage(
                        offstage: _maximizedPane != null && !maximized,
                        child: ExcludeFocus(
                          excluding: _maximizedPane != null && !maximized,
                          child: Container(
                            key: ValueKey('terminal-tile-${pane.id}'),
                            decoration: BoxDecoration(
                              border: maximized
                                  ? null
                                  : Border.all(
                                      width: 2,
                                      color:
                                          manager.activeTab == tab &&
                                              tab.activePane == pane
                                          ? context.colors.accent
                                          : Colors.transparent,
                                    ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GestureDetector(
                                  onTap: () => widget.onActivate(tab, pane),
                                  onSecondaryTapUp: (d) {
                                    manager.activate(tab, pane);
                                    widget.onContextMenu(tab, d.globalPosition);
                                  },
                                  child: Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: context.colors.chip,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: context.colors.border,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.colors.border
                                                .withValues(alpha: .4),
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 20,
                                          ),
                                          child: Text(
                                            '${i + 1}'.padLeft(2, '0'),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.colors.muted,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _statusDot(pane.status),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            pane.server.displayName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        TerminalToolButton(
                                          key: ValueKey(
                                            'terminal-pane-script-${pane.id}',
                                          ),
                                          width: 24,
                                          height: 24,
                                          icon: Icons.code,
                                          label: dt(context, 'longCommand'),
                                          showLabel: false,
                                          onPressed: () =>
                                              widget.onScripts(tab, pane),
                                        ),
                                        if (panes.length > 1)
                                          TerminalToolButton(
                                            width: 24,
                                            height: 24,
                                            icon: maximized
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen,
                                            label: dt(
                                              context,
                                              maximized
                                                  ? 'exitFullscreen'
                                                  : 'fullscreen',
                                            ),
                                            showLabel: false,
                                            onPressed: () {
                                              widget.onActivate(tab, pane);
                                              setState(
                                                () => _maximizedPane = maximized
                                                    ? null
                                                    : pane.id,
                                              );
                                            },
                                          ),
                                        TerminalToolButton(
                                          width: 20,
                                          height: 20,
                                          iconSize: 12,
                                          danger: true,
                                          icon: Icons.close,
                                          label: dt(context, 'close'),
                                          showLabel: false,
                                          onPressed: () =>
                                              manager.closePane(tab, pane),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(child: widget.paneBuilder(tab, pane)),
                                if (widget.showStatusBar)
                                  DesktopTerminalStatusBar(
                                    pane: pane,
                                    monitor: manager.monitor,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (!horizontal &&
                  _maximizedPane == null &&
                  count >= 2 &&
                  count <= 4) ...[
                Positioned(
                  left: _gridColumns.first * (width - 8),
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: _gridDivider(
                    'column-0',
                    (delta) =>
                        _resizeGrid(_gridColumns, 0, delta / (width - 8)),
                  ),
                ),
                if (count >= 3)
                  Positioned(
                    top: _gridRows.first * (height - 8),
                    left: count == 3 ? _gridColumns.first * (width - 8) + 8 : 0,
                    right: 0,
                    height: 8,
                    child: _gridDivider(
                      'row-0',
                      (delta) =>
                          _resizeGrid(_gridRows, 0, delta / (height - 8)),
                      vertical: false,
                    ),
                  ),
              ],
            ],
          ),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: content,
          ),
        );
      },
    );
  }

  Rect _panelRect(
    int index,
    int count,
    int cols,
    int rows,
    Size size,
    bool horizontal,
  ) {
    if (horizontal) return Rect.fromLTWH(index * 508, 0, 500, size.height);
    if (count == 1) return Offset.zero & size;
    if (count >= 5) {
      final row = index ~/ cols;
      final columnsInRow = row == rows - 1 ? count - row * cols : cols;
      final width = size.width / columnsInRow;
      final height = size.height / rows;
      return Rect.fromLTWH(index % cols * width, row * height, width, height);
    }
    final leftWidth = _gridColumns.first * (size.width - 8);
    final rightWidth = size.width - leftWidth - 8;
    final topHeight = _gridRows.first * (size.height - 8);
    if (count == 2 || count == 3 && index == 0) {
      return Rect.fromLTWH(
        index == 0 ? 0 : leftWidth + 8,
        0,
        index == 0 ? leftWidth : rightWidth,
        size.height,
      );
    }
    final col = count == 3 ? 1 : index % 2;
    final row = count == 3 ? index - 1 : index ~/ 2;
    return Rect.fromLTWH(
      col == 0 ? 0 : leftWidth + 8,
      row == 0 ? 0 : topHeight + 8,
      col == 0 ? leftWidth : rightWidth,
      row == 0 ? topHeight : size.height - topHeight - 8,
    );
  }

  void _resizeGrid(List<double> sizes, int index, double delta) {
    final minimum = math.min(.15, .5 / sizes.length);
    final change = delta.clamp(
      minimum - sizes[index],
      sizes[index + 1] - minimum,
    );
    setState(() {
      sizes[index] += change;
      sizes[index + 1] -= change;
    });
  }

  Widget _gridDivider(
    String id,
    ValueChanged<double> onDrag, {
    bool vertical = true,
  }) => TerminalResizeHandle(
    key: ValueKey('terminal-grid-divider-$id'),
    vertical: vertical,
    fullLine: true,
    onDrag: onDrag,
  );
}
