import 'package:flutter/material.dart';

import '../../core/ui/palette.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/coming_soon_placeholder.dart';

class CredentialsPage extends StatelessWidget {
  const CredentialsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: AppBar(
        backgroundColor: AppPalette.canvas,
        centerTitle: true,
        title: Text(l.tr('settings.credentials.title')),
      ),
      body: const ComingSoonPlaceholder(icon: Icons.vpn_key_outlined),
    );
  }
}
