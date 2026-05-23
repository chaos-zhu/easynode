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
      backgroundColor: const Color(0xFFF7EFE0),
      body: SafeArea(child: IndexedStack(index: _index, children: _tabs)),
      bottomNavigationBar: _WarmBottomBar(
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        items: [
          _WarmBottomBarItem(
            icon: Icons.monitor_outlined,
            label: l.tr('tabs.servers'),
          ),
          _WarmBottomBarItem(
            icon: Icons.folder_outlined,
            label: l.tr('tabs.sftp'),
          ),
          _WarmBottomBarItem(
            icon: Icons.article_outlined,
            label: l.tr('tabs.scripts'),
          ),
          _WarmBottomBarItem(
            icon: Icons.settings_outlined,
            label: l.tr('tabs.settings'),
          ),
        ],
      ),
    );
  }
}

class _WarmBottomBar extends StatelessWidget {
  const _WarmBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_WarmBottomBarItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFFF7EFE0),
        padding: const EdgeInsets.fromLTRB(21, 12, 21, 21),
        child: Container(
          height: 62,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF5E6),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFFE2D5B3)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _WarmBottomBarButton(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarmBottomBarButton extends StatelessWidget {
  const _WarmBottomBarButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _WarmBottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF9A8B68);
    return Tooltip(
      message: item.label,
      child: Material(
        color: selected ? const Color(0xFFE5B33A) : Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarmBottomBarItem {
  const _WarmBottomBarItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}
