import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class ScriptsTab extends StatelessWidget {
  const ScriptsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(l.tr('tabs.scripts'))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              l.tr('scripts.placeholder'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
