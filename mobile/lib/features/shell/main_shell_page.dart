import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/auth_notifier.dart';
import '../servers/servers_tab.dart';
import 'scripts_tab.dart';
import 'settings_tab.dart';
import 'sftp_tab.dart';

/// Top-level shell shown after login. Hosts the four bottom-nav tabs the
/// product spec calls for: Servers / SFTP / Scripts / Settings.
///
/// Tabs are kept alive via [IndexedStack] so switching back doesn't refetch.
class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  int _index = 0;

  static const _tabs = <Widget>[
    ServersTab(),
    SftpTab(),
    ScriptsTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    // signOut wipes auth state; AppRoot re-renders to LoginPage automatically.
    // We don't need to handle that here.
    ref.listen(authProvider, (_, _) {});

    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: _tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 56,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dns_outlined),
            selectedIcon: const Icon(Icons.dns),
            label: l.tr('tabs.servers'),
            tooltip: l.tr('tabs.servers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: l.tr('tabs.sftp'),
            tooltip: l.tr('tabs.sftp'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_books_outlined),
            selectedIcon: const Icon(Icons.library_books),
            label: l.tr('tabs.scripts'),
            tooltip: l.tr('tabs.scripts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l.tr('tabs.settings'),
            tooltip: l.tr('tabs.settings'),
          ),
        ],
      ),
    );
  }
}
