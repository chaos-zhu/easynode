import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'app_update_repository.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateCheckResult result,
) async {
  final l = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.tr('settings.update.availableTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.trf('settings.update.versionLine', [
              result.currentVersion,
              result.info.latestVersion,
            ]),
          ),
          if (result.info.features.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.tr('settings.update.notesTitle')),
            const SizedBox(height: 6),
            for (final feature in result.info.features.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $feature'),
              ),
          ],
          if (!result.info.hasReleaseUrl) ...[
            const SizedBox(height: 12),
            Text(l.tr('settings.update.noReleaseUrl')),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: result.info.hasReleaseUrl
              ? () {
                  Navigator.of(dialogContext).pop();
                  launchAppUpdateUrl(result.info.releaseUrl);
                }
              : null,
          child: Text(l.tr('settings.update.openRelease')),
        ),
      ],
    ),
  );
}

Future<bool> launchAppUpdateUrl(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
