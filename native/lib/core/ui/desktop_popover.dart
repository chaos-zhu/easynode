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
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final trigger = context.findRenderObject()! as RenderBox;
  final anchor =
      trigger.localToGlobal(Offset.zero, ancestor: overlay) & trigger.size;
  return navigator.push<T>(
    _DesktopPopoverRoute<T>(
      anchor: anchor,
      width: width ?? anchor.width,
      maxHeight: maxHeight,
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
                child: Material(
                  color: colors.card,
                  surfaceTintColor: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: .16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: builder(context),
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
  const _PopoverLayout(this.anchor, this.width, this.maxHeight, this.padding);
  final Rect anchor;
  final double width;
  final double maxHeight;
  final EdgeInsets padding;
  static const gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final panelWidth = math.min(
      width,
      math.max(0.0, constraints.maxWidth - padding.horizontal),
    );
    final below = constraints.maxHeight - padding.bottom - anchor.bottom - gap;
    final above = anchor.top - padding.top - gap;
    return BoxConstraints(
      minWidth: panelWidth,
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
      anchor.left
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
      padding != oldDelegate.padding;
}
