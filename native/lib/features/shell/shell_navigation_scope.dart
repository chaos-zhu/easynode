import 'package:flutter/widgets.dart';

class ShellNavigationScope extends InheritedWidget {
  const ShellNavigationScope({
    super.key,
    required this.showMenuButton,
    required this.openNavigation,
    required super.child,
  });

  final bool showMenuButton;
  final VoidCallback openNavigation;

  static ShellNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavigationScope>();
  }

  @override
  bool updateShouldNotify(ShellNavigationScope oldWidget) {
    return showMenuButton != oldWidget.showMenuButton ||
        openNavigation != oldWidget.openNavigation;
  }
}
