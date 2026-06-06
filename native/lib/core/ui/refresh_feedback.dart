import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<void> runRefreshWithFeedback(
  BuildContext context,
  Future<void> Function() refresh,
) async {
  try {
    await refresh();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          ).trf('common.refreshFailed', [error.toString()]),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
