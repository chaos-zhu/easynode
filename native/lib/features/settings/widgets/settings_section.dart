import 'package:flutter/material.dart';

import '../../../core/ui/palette.dart';

/// A labelled section in the Settings page: an all-caps header plus a rounded
/// card container that wraps its rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 6),
  });

  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppPalette.muted,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppPalette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(children: _withDividers(children)),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) {
    if (rows.length <= 1) return rows;
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      out.add(rows[i]);
      if (i < rows.length - 1) {
        out.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: AppPalette.border),
          ),
        );
      }
    }
    return out;
  }
}
