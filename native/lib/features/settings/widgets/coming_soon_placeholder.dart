import 'package:flutter/material.dart';

import '../../../core/ui/app_color_theme.dart';
import '../../../l10n/app_localizations.dart';

/// Placeholder shown by settings sub-pages that are not wired up yet.
/// Centered icon + "coming soon" copy + a button to pop back to settings.
class ComingSoonPlaceholder extends StatelessWidget {
  const ComingSoonPlaceholder({super.key, this.icon = Icons.construction});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.colors.chip,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 30, color: context.colors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              l.tr('settings.comingSoon.title'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.tr('settings.comingSoon.body'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.chip,
                foregroundColor: context.colors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              child: Text(l.tr('settings.comingSoon.back')),
            ),
          ],
        ),
      ),
    );
  }
}
