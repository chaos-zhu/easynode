import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/auth_notifier.dart';
import '../../state/locale_notifier.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('settings.logoutConfirmTitle')),
        content: Text(l.tr('settings.logoutConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.tr('settings.logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).signOut();
    }
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final current = ref.read(localeProvider);
    final selected = await showDialog<_LangChoice>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(l.tr('settings.language')),
          children: [
            _LangOption(
              label: l.tr('common.system'),
              selected: current == null,
              value: _LangChoice.system,
            ),
            _LangOption(
              label: l.tr('settings.languageChinese'),
              selected: current?.languageCode == 'zh',
              value: _LangChoice.zh,
            ),
            _LangOption(
              label: l.tr('settings.languageEnglish'),
              selected: current?.languageCode == 'en',
              value: _LangChoice.en,
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    final notifier = ref.read(localeProvider.notifier);
    switch (selected) {
      case _LangChoice.system:
        await notifier.setLocale(null);
      case _LangChoice.zh:
        await notifier.setLocale(const Locale('zh'));
      case _LangChoice.en:
        await notifier.setLocale(const Locale('en'));
    }
  }

  String _languageSubtitle(BuildContext context, Locale? locale) {
    final l = AppLocalizations.of(context);
    if (locale == null) return l.tr('common.system');
    return switch (locale.languageCode) {
      'zh' => l.tr('settings.languageChinese'),
      'en' => l.tr('settings.languageEnglish'),
      _ => locale.languageCode,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(authProvider).session;
    final locale = ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(l.tr('settings.title'))),
      body: ListView(
        children: [
          if (session != null)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(session.username),
              subtitle: Text(session.serverAddress),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings-language'),
            leading: const Icon(Icons.translate),
            title: Text(l.tr('settings.language')),
            subtitle: Text(_languageSubtitle(context, locale)),
            onTap: () => _pickLanguage(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings-logout'),
            leading: const Icon(Icons.logout),
            title: Text(l.tr('settings.logout')),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }
}

enum _LangChoice { system, zh, en }

class _LangOption extends StatelessWidget {
  const _LangOption({
    required this.label,
    required this.selected,
    required this.value,
  });

  final String label;
  final bool selected;
  final _LangChoice value;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(value),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
