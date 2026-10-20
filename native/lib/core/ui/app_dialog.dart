import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared dialog entry point. Desktop dialogs fade and slide like Element Plus;
/// mobile dialogs retain the standard Material route.
/// [closeOnPressEscape] controls Escape independently of [barrierDismissible].
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool closeOnPressEscape = true,
}) {
  Widget buildDialog(BuildContext dialogContext) => FocusScope(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event.logicalKey != LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      if (closeOnPressEscape && event is KeyDownEvent) {
        Navigator.of(dialogContext).maybePop();
      }
      return KeyEventResult.handled;
    },
    child: builder(dialogContext),
  );

  if (!Platform.isMacOS && !Platform.isWindows) {
    return showDialog<T>(
      context: context,
      builder: buildDialog,
      barrierDismissible: barrierDismissible,
    );
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    _DesktopDialogRoute<T>(
      context: context,
      builder: buildDialog,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
      barrierColor:
          DialogTheme.of(context).barrierColor ?? const Color(0x80000000),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class _DesktopDialogRoute<T> extends DialogRoute<T> {
  _DesktopDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierDismissible,
    required super.barrierColor,
    required this.reduceMotion,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final curve = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic
            : Curves.easeOutCubic;
        final progress = curve.transform(animation.value);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, -20 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}
