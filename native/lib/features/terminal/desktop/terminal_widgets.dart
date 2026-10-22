import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../core/ui/desktop_popover.dart';
import '../../../l10n/app_localizations.dart';

String dt(BuildContext context, String key) =>
    AppLocalizations.of(context).tr('desktop.terminal.$key');
void terminalNotice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

/// Web's local SVGs share one optical size and inherit the active theme.
class TerminalIcon extends StatelessWidget {
  const TerminalIcon(this.icon, {super.key, this.size = 16, this.color});
  final IconData icon;
  final double size;
  final Color? color;
  static final _assets = {
    Icons.memory: 'cpu',
    Icons.link: 'connection',
    Icons.developer_board_outlined: 'memory',
    Icons.fullscreen: 'maximize',
    Icons.fullscreen_exit: 'restore',
    Icons.monitor_heart_outlined: 'status',
    Icons.folder_open_outlined: 'sftp',
    Icons.chat_bubble_outline: 'chat-dot-round',
    Icons.layers_outlined: 'docker',
    Icons.sync_alt: 'sync',
    Icons.vertical_split_outlined: 'split-horizontal',
    Icons.horizontal_split_outlined: 'split-vertical',
    Icons.arrow_back: 'arrow-left',
    Icons.arrow_forward: 'arrow-right',
    Icons.keyboard_arrow_down: 'arrow-down',
    Icons.refresh: 'refresh',
    Icons.restart_alt: 'refresh-right',
    Icons.article_outlined: 'document',
    Icons.stop_outlined: 'video-pause',
    Icons.delete_outline: 'delete',
    Icons.edit_outlined: 'edit',
    Icons.search: 'search',
    Icons.copy_outlined: 'document-copy',
    Icons.visibility: 'view',
    Icons.visibility_off_outlined: 'hide',
    Icons.settings_outlined: 'setting',
    Icons.home: 'home-filled',
    Icons.play_arrow_outlined: 'video-play',
    Icons.close: 'close',
    Icons.add: 'plus',
    Icons.download: 'download',
    Icons.upload: 'upload',
  };
  @override
  Widget build(BuildContext context) {
    final asset = _assets[icon];
    return asset == null
        ? Icon(icon, size: size, color: color)
        : SvgPicture.asset(
            'assets/terminal/icons/$asset.svg',
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(
              color ?? IconTheme.of(context).color ?? context.colors.text,
              BlendMode.srcIn,
            ),
          );
  }
}

class TerminalToolButton extends StatelessWidget {
  const TerminalToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.showLabel = true,
    this.width,
    this.color,
    this.height = 30,
    this.iconSize = 16,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool showLabel;
  final double? width;
  final Color? color;
  final double height, iconSize;
  final bool danger;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: showLabel ? '' : label,
    child: TextButton(
      onPressed: onPressed,
      style:
          TextButton.styleFrom(
            foregroundColor: selected
                ? context.colors.success
                : color ?? context.colors.text,
            backgroundColor: Colors.transparent,
            minimumSize: Size(width ?? 30, height),
            padding: EdgeInsets.symmetric(
              horizontal: showLabel
                  ? 9
                  : width == null
                  ? 7
                  : 0,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            splashFactory: NoSplash.splashFactory,
            textStyle: const TextStyle(fontWeight: FontWeight.w400),
          ).copyWith(
            backgroundColor: danger
                ? WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered)
                        ? context.colors.danger
                        : Colors.transparent,
                  )
                : null,
            foregroundColor: danger
                ? WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered)
                        ? Colors.white
                        : context.colors.muted,
                  )
                : null,
          ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TerminalIcon(icon, size: iconSize),
          if (showLabel) ...[
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    ),
  );
}

/// Compact text menus and inline switches mirror the desktop Web toolbar.
class TerminalMenuButton extends StatelessWidget {
  const TerminalMenuButton({
    super.key,
    required this.label,
    this.dropdown = false,
    this.onPressed,
    this.outlined = false,
  });
  final String label;
  final bool dropdown;
  final bool outlined;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: context.colors.text,
      minimumSize: Size(0, outlined ? 24 : 30),
      padding: EdgeInsets.symmetric(horizontal: outlined ? 9 : 5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      textStyle: const TextStyle(fontWeight: FontWeight.w400),
      side: outlined ? BorderSide(color: context.colors.border) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: outlined ? 12 : 14)),
        if (dropdown)
          const Padding(
            padding: EdgeInsets.only(left: 3),
            child: TerminalIcon(Icons.keyboard_arrow_down, size: 12),
          ),
      ],
    ),
  );
}

class TerminalToggle extends StatelessWidget {
  const TerminalToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
    this.activeColor,
    this.inactiveColor,
  });
  final String label;
  final String? tooltip;
  final Color? activeColor, inactiveColor;
  final bool value;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Semantics(
      toggled: value,
      button: true,
      label: label,
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          color: value
              ? activeColor ?? context.colors.success
              : inactiveColor ?? context.colors.danger,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onChanged,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!value)
                    const Icon(Icons.circle, size: 16, color: Colors.white),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (value)
                    const Icon(Icons.circle, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The Web layout control is a mutually exclusive radio group, not a switch.
class TerminalLayoutSelector extends StatelessWidget {
  const TerminalLayoutSelector({
    super.key,
    required this.horizontal,
    required this.onChanged,
  });
  final bool horizontal;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in [false, true])
            Semantics(
              selected: horizontal == value,
              child: TextButton(
                key: Key(
                  value ? 'terminal-horizontal-toggle' : 'terminal-fit-grid',
                ),
                onPressed: () => onChanged(value),
                style: TextButton.styleFrom(
                  foregroundColor: horizontal == value
                      ? context.colors.fontOnPrimary
                      : context.colors.text,
                  backgroundColor: horizontal == value
                      ? context.colors.accent
                      : context.colors.card,
                  minimumSize: const Size(0, 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(value ? 0 : 2),
                      right: Radius.circular(value ? 2 : 0),
                    ),
                  ),
                  splashFactory: NoSplash.splashFactory,
                ),
                child: Text(
                  dt(context, value ? 'horizontalGrid' : 'fitGrid'),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// An unobtrusive drag target shared by terminal and auxiliary panels.
class TerminalResizeHandle extends StatefulWidget {
  const TerminalResizeHandle({
    super.key,
    required this.vertical,
    required this.onDrag,
    this.onEnd,
    this.fullLine = false,
  });
  final bool vertical, fullLine;
  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;

  @override
  State<TerminalResizeHandle> createState() => _TerminalResizeHandleState();
}

class _TerminalResizeHandleState extends State<TerminalResizeHandle> {
  bool _hovered = false, _dragging = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.vertical
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => setState(() => _dragging = true),
      onPanUpdate: (details) =>
          widget.onDrag(widget.vertical ? details.delta.dx : details.delta.dy),
      onPanEnd: (_) {
        setState(() => _dragging = false);
        widget.onEnd?.call();
      },
      onPanCancel: () => setState(() => _dragging = false),
      child: SizedBox(
        width: widget.vertical ? 8 : null,
        height: widget.vertical ? null : 8,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: widget.vertical
                ? 2
                : widget.fullLine
                ? double.infinity
                : 40,
            height: widget.vertical
                ? widget.fullLine
                      ? double.infinity
                      : 40
                : 2,
            decoration: BoxDecoration(
              color: _hovered || _dragging
                  ? context.colors.accent
                  : widget.fullLine
                  ? context.colors.border
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    ),
  );
}

class TerminalMenuAction {
  const TerminalMenuAction(
    this.id,
    this.label,
    this.icon, {
    this.enabled = true,
    this.danger = false,
    this.children = const [],
  });
  final String id, label;
  final IconData icon;
  final bool enabled, danger;
  final List<TerminalMenuAction> children;
}

Future<String?> showTerminalMenu(
  BuildContext context,
  List<TerminalMenuAction> actions, {
  Offset? position,
}) => showDesktopPopover<String>(
  context: context,
  width: 240,
  maxHeight: 520,
  position: position,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final action in actions)
          TextButton(
            onPressed: action.enabled
                ? () => Navigator.pop(context, action.id)
                : null,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: action.danger
                  ? context.colors.danger
                  : context.colors.text,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
              shape: const RoundedRectangleBorder(),
            ),
            child: Row(
              children: [
                TerminalIcon(action.icon),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    action.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  ),
);
