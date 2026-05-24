import 'package:flutter/material.dart';

import '../../core/ui/palette.dart';

/// Unified header used by every bottom-nav tab. Fixed [height] and font size
/// keep the layout from jumping when the user switches tabs; the left-aligned
/// [title] sits on a [Stack] so optional [actions] on the right don't shift it.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.text,
                  letterSpacing: -0.2,
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
