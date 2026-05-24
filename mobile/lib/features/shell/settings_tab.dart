import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/palette.dart';
import '../../l10n/app_localizations.dart';
import '../../state/auth_notifier.dart';
import '../../state/credential_list_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/locale_notifier.dart';
import '../../state/script_list_notifier.dart';
import '../settings/account_security_page.dart';
import '../settings/credentials_page.dart';
import '../settings/plus_subscription_page.dart';
import '../settings/proxy_page.dart';
import '../settings/sessions_page.dart';
import '../settings/widgets/settings_row.dart';
import '../settings/widgets/settings_section.dart';

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

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _showNotifications(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.tr('settings.notifications.tooltip'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.text,
                  ),
                ),
                const SizedBox(height: 20),
                Icon(
                  Icons.notifications_off_outlined,
                  size: 36,
                  color: AppPalette.softMuted,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('settings.notifications.empty'),
                  style: const TextStyle(fontSize: 13, color: AppPalette.muted),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showThemeWip(BuildContext context) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.tr('settings.theme.wipToast')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(authProvider).session;
    final locale = ref.watch(localeProvider);
    final hostCount = ref.watch(hostListProvider).valueOrNull?.length ?? 0;
    final credentialCount =
        ref.watch(credentialListProvider).valueOrNull?.length ?? 0;
    final scriptCount = ref.watch(scriptListProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                title: l.tr('settings.title'),
                onBellTap: () => _showNotifications(context),
              ),
            ),
            SliverToBoxAdapter(
              child: _ProfileCard(
                username: session?.username ?? '-',
                serverAddress: session?.serverAddress ?? '',
                hostCount: hostCount,
                credentialCount: credentialCount,
                scriptCount: scriptCount,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsSection(
                title: l.tr('settings.section.subscription'),
                children: [
                  SettingsRow(
                    icon: Icons.workspace_premium_outlined,
                    title: l.tr('settings.plus.title'),
                    subtitle: l.tr('settings.plus.inactiveMeta'),
                    trailing: _StatusChip(
                      label: l.tr('settings.plus.inactive'),
                      tone: _ChipTone.muted,
                    ),
                    onTap: () => _push(context, const PlusSubscriptionPage()),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsSection(
                title: l.tr('settings.section.security'),
                children: [
                  SettingsRow(
                    icon: Icons.lock_outline,
                    title: l.tr('settings.account.title'),
                    subtitle: l.tr('settings.account.subtitle'),
                    onTap: () => _push(context, const AccountSecurityPage()),
                  ),
                  SettingsRow(
                    icon: Icons.devices_outlined,
                    title: l.tr('settings.sessions.title'),
                    subtitle: l.tr('settings.sessions.subtitle'),
                    onTap: () => _push(context, const SessionsPage()),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsSection(
                title: l.tr('settings.section.connection'),
                children: [
                  SettingsRow(
                    icon: Icons.vpn_key_outlined,
                    title: l.tr('settings.credentials.title'),
                    subtitle: l.tr('settings.credentials.subtitle'),
                    onTap: () => _push(context, const CredentialsPage()),
                  ),
                  SettingsRow(
                    icon: Icons.cloud_outlined,
                    title: l.tr('settings.proxy.title'),
                    subtitle: l.tr('settings.proxy.subtitle'),
                    onTap: () => _push(context, const ProxyPage()),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsSection(
                title: l.tr('settings.section.preferences'),
                children: [
                  SettingsRow(
                    key: const Key('settings-language'),
                    icon: Icons.translate,
                    title: l.tr('settings.language'),
                    subtitle: _languageSubtitle(context, locale),
                    onTap: () => _pickLanguage(context, ref),
                  ),
                  SettingsRow(
                    icon: Icons.palette_outlined,
                    title: l.tr('settings.theme.title'),
                    trailing: _StatusChip(
                      label: l.tr('settings.theme.wipChip'),
                      tone: _ChipTone.muted,
                    ),
                    onTap: () => _showThemeWip(context),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: _LogoutButton(
                  label: l.tr('settings.logout'),
                  onTap: () => _confirmLogout(context, ref),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBellTap});

  final String title;
  final VoidCallback onBellTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppPalette.text,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Material(
            color: AppPalette.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppPalette.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onBellTap,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.notifications_none_outlined,
                  size: 20,
                  color: AppPalette.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.username,
    required this.serverAddress,
    required this.hostCount,
    required this.credentialCount,
    required this.scriptCount,
  });

  final String username;
  final String serverAddress;
  final int hostCount;
  final int credentialCount;
  final int scriptCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppPalette.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppPalette.accent, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: l.tr('settings.plus.inactive'),
                            tone: _ChipTone.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        serverAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.softMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.chip,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _ProfileStat(
                    value: hostCount,
                    label: l.tr('settings.profile.hostsLabel'),
                  ),
                  const _StatDivider(),
                  _ProfileStat(
                    value: credentialCount,
                    label: l.tr('settings.profile.credentialsLabel'),
                  ),
                  const _StatDivider(),
                  _ProfileStat(
                    value: scriptCount,
                    label: l.tr('settings.profile.scriptsLabel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppPalette.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppPalette.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppPalette.border);
  }
}

enum _ChipTone { muted, accent, success }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _ChipTone.muted => (AppPalette.chip, AppPalette.muted),
      _ChipTone.accent => (AppPalette.accentSoft, AppPalette.primary),
      _ChipTone.success => (
        AppPalette.success.withValues(alpha: 0.16),
        AppPalette.success,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.dangerSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('settings-logout'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.dangerBorder),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout, size: 18, color: AppPalette.danger),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.danger,
                ),
              ),
            ],
          ),
        ),
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
