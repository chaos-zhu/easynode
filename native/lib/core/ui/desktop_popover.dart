import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_color_theme.dart';

/// An anchored desktop panel, shared by form selects and the date picker.
Future<T?> showDesktopPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? width,
  double maxHeight = 280,
  Offset? position,
  bool shrinkWrapWidth = false,
  bool dropdown = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final trigger = context.findRenderObject()! as RenderBox;
  final anchor = position == null
      ? trigger.localToGlobal(Offset.zero, ancestor: overlay) & trigger.size
      : position & Size.zero;
  return navigator.push<T>(
    _DesktopPopoverRoute<T>(
      anchor: anchor,
      width: width ?? anchor.width,
      maxHeight: maxHeight,
      shrinkWrapWidth: shrinkWrapWidth,
      dropdown: dropdown,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class _DesktopPopoverRoute<T> extends PopupRoute<T> {
  _DesktopPopoverRoute({
    required this.anchor,
    required this.width,
    required this.maxHeight,
    required this.shrinkWrapWidth,
    required this.dropdown,
    required this.builder,
    required this.themes,
    required this.barrierLabel,
    required this.reduceMotion,
  }) : super(
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         requestFocus: true,
       );

  final Rect anchor;
  final double width;
  final double maxHeight;
  final bool shrinkWrapWidth;
  final bool dropdown;
  final WidgetBuilder builder;
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
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    Builder(
      builder: (context) {
        final colors = context.colors;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: CustomSingleChildLayout(
            delegate: _PopoverLayout(
              anchor,
              width,
              maxHeight,
              MediaQuery.paddingOf(context) + const EdgeInsets.all(8),
              shrinkWrapWidth,
              dropdown,
            ),
            child: FadeTransition(
              opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
              child: SlideTransition(
                position: animation.drive(
                  Tween(
                    begin: const Offset(0, -.02),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: CustomPaint(
                  foregroundPainter: dropdown
                      ? _DropdownArrow(
                          anchor: anchor,
                          viewport: MediaQuery.sizeOf(context),
                          padding:
                              MediaQuery.paddingOf(context) +
                              const EdgeInsets.all(8),
                          color: colors.card,
                          border: colors.border,
                        )
                      : null,
                  child: Material(
                    color: colors.card,
                    surfaceTintColor: Colors.transparent,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: .16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(dropdown ? 4 : 6),
                      side: BorderSide(color: colors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: builder(context),
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

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(
    this.anchor,
    this.width,
    this.maxHeight,
    this.padding,
    this.shrinkWrapWidth,
    this.dropdown,
  );
  final Rect anchor;
  final double width;
  final double maxHeight;
  final EdgeInsets padding;
  final bool shrinkWrapWidth;
  final bool dropdown;
  double get gap => dropdown ? 12 : 6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final panelWidth = math.min(
      width,
      math.max(0.0, constraints.maxWidth - padding.horizontal),
    );
    final below = constraints.maxHeight - padding.bottom - anchor.bottom - gap;
    final above = anchor.top - padding.top - gap;
    return BoxConstraints(
      minWidth: shrinkWrapWidth ? 0 : panelWidth,
      maxWidth: panelWidth,
      maxHeight: math.min(maxHeight, math.max(0, math.max(below, above))),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + gap;
    final y = below + childSize.height <= size.height - padding.bottom
        ? below
        : anchor.top - gap - childSize.height;
    return Offset(
      (dropdown ? anchor.center.dx - childSize.width / 2 : anchor.left)
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
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      maxHeight != oldDelegate.maxHeight ||
      padding != oldDelegate.padding ||
      shrinkWrapWidth != oldDelegate.shrinkWrapWidth ||
      dropdown != oldDelegate.dropdown;
}

/// Element dropdown pointer follows the trigger even when the menu is clamped
/// against a window edge. Ordinary form popovers retain their existing style.
class _DropdownArrow extends CustomPainter {
  const _DropdownArrow({
    required this.anchor,
    required this.viewport,
    required this.padding,
    required this.color,
    required this.border,
  });
  final Rect anchor;
  final Size viewport;
  final EdgeInsets padding;
  final Color color, border;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _PopoverLayout(
      anchor,
      size.width,
      size.height,
      padding,
      false,
      true,
    );
    final offset = layout.getPositionForChild(viewport, size);
    final x = (anchor.center.dx - offset.dx)
        .clamp(10.0, math.max(10.0, size.width - 10))
        .toDouble();
    final below = offset.dy >= anchor.bottom;
    final edge = below ? 0.0 : size.height;
    final direction = below ? -1.0 : 1.0;
    final fill = Path()
      ..moveTo(x - 6, edge - direction)
      ..lineTo(x, edge + direction * 6)
      ..lineTo(x + 6, edge - direction)
      ..close();
    canvas.drawPath(fill, Paint()..color = color);
    final outline = Path()
      ..moveTo(x - 6, edge)
      ..lineTo(x, edge + direction * 6)
      ..lineTo(x + 6, edge);
    canvas.drawPath(
      outline,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DropdownArrow old) =>
      anchor != old.anchor ||
      viewport != old.viewport ||
      padding != old.padding ||
      color != old.color ||
      border != old.border;
}
