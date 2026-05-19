import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class SftpTab extends StatelessWidget {
  const SftpTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _PlaceholderTab(
      title: l.tr('tabs.sftp'),
      icon: Icons.folder_outlined,
      message: l.tr('sftp.placeholder'),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
