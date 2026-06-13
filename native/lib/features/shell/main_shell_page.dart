import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/palette.dart';
import '../../features/settings/app_update_prompt.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_update_notifier.dart';
import '../../state/auth_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/terminal_providers.dart';
import '../servers/servers_tab.dart';
import 'scripts_tab.dart';
import 'settings_tab.dart';
import 'sftp_session_manager.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkUpdatesSilently(),
    );
  }

  Future<void> _checkUpdatesSilently() async {
    final result = await ref.read(appUpdateProvider.notifier).check();
    if (!mounted || result == null || !result.hasUpdate) return;
    await showAppUpdateDialog(context, result);
  }

  @override
  Widget build(BuildContext context) {
    // signOut wipes auth state; AppRoot re-renders to LoginPage automatically.
    // We don't need to handle that here.
    ref.listen(authProvider, (_, _) {});
    // Eager-load Plus status so gating UI in Scripts / Server form can read
    // it synchronously without each page firing its own request.
    ref.watch(plusInfoProvider);

    final l = AppLocalizations.of(context);
    final sftpManager = ref.watch(sftpSessionManagerProvider);
    return AnimatedBuilder(
      animation: sftpManager,
      builder: (context, child) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_canGoUpInSftp(sftpManager)) {
              sftpManager.goParent();
            } else {
              _confirmExit(context);
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: AppPalette.canvas,
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 90),
            child: IndexedStack(index: _index, children: _tabs),
          ),
        ),
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
      ),
    );
  }

  bool _canGoUpInSftp(SftpSessionManager manager) {
    if (_index != 1) return false;
    final session = manager.activeSession;
    if (session == null) return false;
    if (session.status != SftpConnectionStatus.connected) return false;
    final path = session.currentPath;
    return path.isNotEmpty && path != '/' && path != '~';
  }

  Future<void> _confirmExit(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('common.exitAppTitle')),
        content: Text(l.tr('common.exitAppBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('common.exitApp')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SystemNavigator.pop();
    }
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
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppPalette.canvas.withValues(alpha: 0),
            AppPalette.canvas.withValues(alpha: 0.55),
            AppPalette.canvas.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(21, 12, 21, 8 + bottomPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 62,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppPalette.card,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: AppPalette.border),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: _indicatorAlignment,
                    child: FractionallySizedBox(
                      widthFactor: 1 / items.length,
                      heightFactor: 1,
                      child: const _WarmBottomBarIndicator(),
                    ),
                  ),
                  Row(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Alignment get _indicatorAlignment {
    if (items.length <= 1) return Alignment.center;
    final step = 2 / (items.length - 1);
    return Alignment(-1 + (step * selectedIndex), 0);
  }
}

class _WarmBottomBarIndicator extends StatelessWidget {
  const _WarmBottomBarIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppPalette.accent.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: AppPalette.accent.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
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
    final color = selected ? Colors.white : AppPalette.softMuted;
    return Tooltip(
      message: item.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: IconTheme(
            data: IconThemeData(size: 22, color: color),
            child: Center(child: Icon(item.icon)),
          ),
        ),
      ),
    );
  }
}

class _WarmBottomBarItem {
  const _WarmBottomBarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
