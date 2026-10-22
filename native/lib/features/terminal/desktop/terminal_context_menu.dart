import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/app_color_theme.dart';
import 'terminal_widgets.dart';

/// Text-only context menu with hover submenus, matching Web's terminal menu.
Future<String?> showTerminalContextMenu(
  BuildContext context,
  List<TerminalMenuAction> actions,
  Offset position,
) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierColor: Colors.transparent,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: const Duration(milliseconds: 120),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (_, _, _) =>
      _TerminalContextMenu(actions: actions, position: position),
);

class _TerminalContextMenu extends StatefulWidget {
  const _TerminalContextMenu({required this.actions, required this.position});
  final List<TerminalMenuAction> actions;
  final Offset position;
  @override
  State<_TerminalContextMenu> createState() => _TerminalContextMenuState();
}

class _TerminalContextMenuState extends State<_TerminalContextMenu> {
  int? _active;
  double _columnWidth(List<TerminalMenuAction> actions) {
    var width = 160.0;
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(
          text: action.label,
          style: const TextStyle(fontSize: 13),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width = math.max(
        width,
        painter.width + 32 + (action.children.isEmpty ? 0 : 18),
      );
      painter.dispose();
    }
    return width.clamp(160, 350);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = _columnWidth(widget.actions);
    final height = math.min(
      widget.actions.length * 32.0 + 10,
      size.height - 16,
    );
    final x = widget.position.dx.clamp(
      8.0,
      math.max(8.0, size.width - width - 8),
    );
    final y = widget.position.dy.clamp(
      8.0,
      math.max(8.0, size.height - height - 8),
    );
    final children = _active == null
        ? <TerminalMenuAction>[]
        : widget.actions[_active!].children;
    final subHeight = math.min(children.length * 32.0 + 10, size.height - 16);
    final subWidth = _columnWidth(children);
    final subX = x + width + subWidth + 4 <= size.width
        ? x + width + 2
        : x - subWidth - 2;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned(
              left: x.toDouble(),
              top: y.toDouble(),
              width: width,
              child: _panel(widget.actions, height, root: true),
            ),
            if (children.isNotEmpty)
              Positioned(
                left: subX
                    .clamp(8.0, math.max(8.0, size.width - subWidth - 8))
                    .toDouble(),
                top: (y + _active! * 32)
                    .clamp(8.0, math.max(8.0, size.height - subHeight - 8))
                    .toDouble(),
                width: subWidth,
                child: _panel(children, subHeight),
              ),
          ],
        ),
      ),
    );
  }

  Widget _panel(
    List<TerminalMenuAction> actions,
    double maxHeight, {
    bool root = false,
  }) => Material(
    color: context.colors.card,
    surfaceTintColor: Colors.transparent,
    elevation: 6,
    shadowColor: Colors.black.withValues(alpha: .18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: context.colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++)
              MouseRegion(
                onEnter: (_) {
                  if (root) {
                    setState(
                      () => _active = actions[i].children.isEmpty ? null : i,
                    );
                  }
                },
                child: TextButton(
                  onPressed: !actions[i].enabled
                      ? null
                      : () {
                          if (actions[i].children.isNotEmpty) {
                            setState(() => _active = i);
                          } else {
                            Navigator.pop(context, actions[i].id);
                          }
                        },
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: actions[i].danger
                        ? context.colors.danger
                        : context.colors.text,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: const RoundedRectangleBorder(),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: root && _active == i
                        ? context.colors.accentSoft
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          actions[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (actions[i].children.isNotEmpty)
                        const Icon(Icons.chevron_right, size: 14),
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
