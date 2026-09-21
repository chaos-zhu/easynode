import 'package:flutter/material.dart';

import '../../core/ui/app_color_theme.dart';
import 'shell_navigation_scope.dart';

/// Unified header used by every top-level module. Fixed [height] and font size
/// keep the layout from jumping when the user switches tabs; the left-aligned
/// [title] sits on a [Stack] so optional [actions] on the right don't shift it.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final navigation = ShellNavigationScope.maybeOf(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
        child: Row(
          children: [
            if (navigation?.showMenuButton == true) ...[
              IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onPressed: navigation!.openNavigation,
                icon: const Icon(Icons.menu),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                  letterSpacing: 0,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
