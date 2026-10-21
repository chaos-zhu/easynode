import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import 'app_color_theme.dart';

@immutable
class DesktopDropdownItem<T extends Object> {
  const DesktopDropdownItem({
    required this.value,
    required this.label,
    required this.icon,
    this.divided = false,
    this.danger = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool divided;
  final bool danger;
  final bool enabled;
}

/// Compact desktop dropdown with a single fade/scale transition, rather than
/// Material popup menus' staggered item and width/height animations.
class DesktopDropdownMenu<T extends Object> extends StatefulWidget {
  const DesktopDropdownMenu({
    super.key,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.width = 172,
    this.buttonSize = const Size(36, 36),
  });

  final String tooltip;
  final List<DesktopDropdownItem<T>> items;
  final ValueChanged<T> onSelected;
  final double width;
  final Size buttonSize;

  @override
  State<DesktopDropdownMenu<T>> createState() => _DesktopDropdownMenuState<T>();
}

class _DesktopDropdownMenuState<T extends Object>
    extends State<DesktopDropdownMenu<T>> {
  bool _open = false;

  Future<void> _showMenu() async {
    if (_open || widget.items.isEmpty) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    Rect anchorRect() {
      final button = context.findRenderObject()! as RenderBox;
      return button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    }

    setState(() => _open = true);
    final result = await navigator.push<T>(
      _DesktopDropdownRoute<T>(
        anchorRect: anchorRect,
        width: MediaQuery.textScalerOf(context).scale(widget.width),
        items: widget.items,
        label: widget.tooltip,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (result != null) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: _open,
    child: SizedBox.fromSize(
      size: widget.buttonSize,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.items.isEmpty ? null : _showMenu,
        padding: EdgeInsets.zero,
        iconSize: 18,
        style: IconButton.styleFrom(
          minimumSize: widget.buttonSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: _open ? context.colors.accent : context.colors.muted,
          backgroundColor: _open
              ? context.colors.accentSoft
              : Colors.transparent,
          hoverColor: context.colors.accentSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: const Icon(Icons.more_horiz),
      ),
    ),
  );
}

class _DesktopDropdownRoute<T extends Object> extends PopupRoute<T> {
  _DesktopDropdownRoute({
    required this.anchorRect,
    required this.width,
    required this.items,
    required this.label,
    required this.barrierLabel,
    required this.themes,
    required this.reduceMotion,
  }) : super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final Rect Function() anchorRect;
  final double width;
  final List<DesktopDropdownItem<T>> items;
  final String label;
  final CapturedThemes themes;
  final bool reduceMotion;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    Builder(
      builder: (context) {
        final colors = context.colors;
        final firstEnabled = items.indexWhere((item) => item.enabled);
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                FocusScope.of(context).nextFocus(),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                FocusScope.of(context).previousFocus(),
          },
          child: LayoutBuilder(
            builder: (context, constraints) => CustomSingleChildLayout(
              delegate: _DropdownLayout(
                anchorRect(),
                width,
                MediaQuery.paddingOf(context) + const EdgeInsets.all(8),
              ),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final progress = Curves.easeOutCubic.transform(
                    animation.value,
                  );
                  return Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: .96 + .04 * progress,
                      alignment: Alignment.topRight,
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: colors.card,
                  surfaceTintColor: Colors.transparent,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: .18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Semantics(
                    role: SemanticsRole.menu,
                    scopesRoute: true,
                    namesRoute: true,
                    label: label,
                    explicitChildNodes: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0 && items[i].divided)
                              Divider(height: 9, color: colors.border),
                            _DropdownButton<T>(
                              item: items[i],
                              autofocus: i == firstEnabled,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _DropdownButton<T extends Object> extends StatefulWidget {
  const _DropdownButton({required this.item, required this.autofocus});

  final DesktopDropdownItem<T> item;
  final bool autofocus;

  @override
  State<_DropdownButton<T>> createState() => _DropdownButtonState<T>();
}

class _DropdownButtonState<T extends Object> extends State<_DropdownButton<T>> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;
    return Semantics(
      role: SemanticsRole.menuItem,
      child: TextButton(
        autofocus: widget.autofocus,
        focusNode: _focusNode,
        onHover: (hovered) {
          if (hovered && item.enabled) _focusNode.requestFocus();
        },
        onPressed: item.enabled
            ? () => Navigator.of(context).pop<T>(item.value)
            : null,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return colors.softMuted;
            if (item.danger) return colors.danger;
            return states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? colors.accent
                : colors.text;
          }),
          overlayColor: WidgetStatePropertyAll(
            item.danger ? colors.dangerSoft : colors.accentSoft,
          ),
          splashFactory: NoSplash.splashFactory,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 16),
            const SizedBox(width: 9),
            Expanded(child: Text(item.label)),
          ],
        ),
      ),
    );
  }
}

/// Align to the trigger's right edge; open upward when space below is limited.
class _DropdownLayout extends SingleChildLayoutDelegate {
  const _DropdownLayout(this.anchor, this.width, this.padding);

  final Rect anchor;
  final double width;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: math.min(
          width,
          math.max(0, constraints.maxWidth - padding.horizontal),
        ),
        maxWidth: math.min(
          width,
          math.max(0, constraints.maxWidth - padding.horizontal),
        ),
        maxHeight: math.max(0, constraints.maxHeight - padding.vertical),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const gap = 6;
    final x = anchor.right - childSize.width;
    final below = anchor.bottom + gap;
    final y = below + childSize.height <= size.height - padding.bottom
        ? below
        : anchor.top - gap - childSize.height;
    return Offset(
      x
          .clamp(
            padding.left,
            math.max(
              padding.left,
              size.width - padding.right - childSize.width,
            ),
          )
          .toDouble(),
      y
          .clamp(
            padding.top,
            math.max(
              padding.top,
              size.height - padding.bottom - childSize.height,
            ),
          )
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_DropdownLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      padding != oldDelegate.padding;
}
