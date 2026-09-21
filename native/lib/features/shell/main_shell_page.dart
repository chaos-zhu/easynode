import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../features/scheduled_tasks/scheduled_tasks_tab.dart';
import '../../features/settings/app_update_prompt.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_update_notifier.dart';
import '../../state/auth_notifier.dart';
import '../../state/server_data_refresh.dart';
import '../../state/tab_order_notifier.dart';
import '../../state/terminal_providers.dart';
import '../docker/docker_icon.dart';
import '../docker/docker_tab.dart';
import '../servers/servers_tab.dart';
import 'scripts_tab.dart';
import 'settings_tab.dart';
import 'sftp_session_manager.dart';
import 'sftp_tab.dart';
import 'shell_navigation_scope.dart';

class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late String _selectedModule;
  int? _navigationPointer;
  Offset? _navigationDragStart;

  static final _moduleBuilders = <String, Widget Function()>{
    'settings': () => const SettingsTab(),
    'scheduledTasks': () => const ScheduledTasksTab(),
    'scripts': () => const ScriptsTab(),
    'servers': () => const ServersTab(),
    'sftp': () => const SftpTab(),
    'docker': () => const DockerTab(),
  };

  @override
  void initState() {
    super.initState();
    final order = ref.read(tabOrderProvider);
    final home = ref.read(homeTabProvider);
    _selectedModule = order.contains(home) ? home : order.first;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkUpdatesSilently(),
    );
  }

  Future<void> _checkUpdatesSilently() async {
    final result = await ref.read(appUpdateProvider.notifier).check();
    if (!mounted || result == null || !result.hasUpdate) return;
    await showAppUpdateDialog(context, result);
  }

  void _selectModule(String key) {
    if (!_moduleBuilders.containsKey(key)) return;
    if (_selectedModule != key) setState(() => _selectedModule = key);
  }

  void _handleNavigationPointerDown(PointerDownEvent event) {
    if (_navigationPointer != null) return;
    _navigationPointer = event.pointer;
    _navigationDragStart = event.position;
  }

  void _handleNavigationPointerMove(PointerMoveEvent event) {
    if (_navigationPointer != event.pointer || _navigationDragStart == null) {
      return;
    }
    final delta = event.position - _navigationDragStart!;
    if (delta.dx < 0) return;
    if (delta.dx < 56 || delta.dx < delta.dy.abs() * 1.25) return;
    _resetNavigationPointer(event.pointer);
    _scaffoldKey.currentState?.openDrawer();
  }

  void _resetNavigationPointer(int pointer) {
    if (_navigationPointer != pointer) return;
    _navigationPointer = null;
    _navigationDragStart = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, _) {});
    ref.watch(serverSharedDataBootstrapProvider);
    final order = ref
        .watch(tabOrderProvider)
        .where(_moduleBuilders.containsKey)
        .toList(growable: false);
    if (!order.contains(_selectedModule) && order.isNotEmpty) {
      _selectedModule = order.first;
    }
    final selectedIndex = order
        .indexOf(_selectedModule)
        .clamp(0, order.length - 1);
    final sftpManager = ref.watch(sftpSessionManagerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final extended = constraints.maxWidth >= 1100;
        final content = ShellNavigationScope(
          showMenuButton: compact,
          openNavigation: () => _scaffoldKey.currentState?.openDrawer(),
          child: IndexedStack(
            index: selectedIndex,
            children: order
                .map(
                  (key) => _LazyModule(
                    key: ValueKey(key),
                    active: key == _selectedModule,
                    builder: _moduleBuilders[key]!,
                  ),
                )
                .toList(),
          ),
        );
        final pageBody = SafeArea(
          bottom: false,
          child: compact
              ? content
              : Row(
                  children: [
                    _AppNavigationRail(
                      order: order,
                      selectedIndex: selectedIndex,
                      extended: extended,
                      onSelected: (index) => _selectModule(order[index]),
                    ),
                    VerticalDivider(width: 1, color: context.colors.border),
                    Expanded(child: content),
                  ],
                ),
        );

        return AnimatedBuilder(
          animation: sftpManager,
          builder: (context, child) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_scaffoldKey.currentState?.isDrawerOpen == true) {
                Navigator.of(context).pop();
              } else if (_canGoUpInSftp(sftpManager)) {
                sftpManager.goParent();
              } else {
                _confirmExit(context);
              }
            },
            child: child!,
          ),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: context.colors.canvas,
            drawerEnableOpenDragGesture: false,
            drawer: compact
                ? _AppNavigationDrawer(
                    order: order,
                    selectedKey: _selectedModule,
                    onSelected: (key) {
                      Navigator.of(context).pop();
                      _selectModule(key);
                    },
                  )
                : null,
            body: compact
                ? Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _handleNavigationPointerDown,
                    onPointerMove: _handleNavigationPointerMove,
                    onPointerUp: (event) =>
                        _resetNavigationPointer(event.pointer),
                    onPointerCancel: (event) =>
                        _resetNavigationPointer(event.pointer),
                    child: pageBody,
                  )
                : pageBody,
          ),
        );
      },
    );
  }

  bool _canGoUpInSftp(SftpSessionManager manager) {
    if (_selectedModule != 'sftp') return false;
    final session = manager.activeSession;
    if (session == null || session.status != SftpConnectionStatus.connected) {
      return false;
    }
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
    if (confirmed == true) await SystemNavigator.pop();
  }
}

class _LazyModule extends StatefulWidget {
  const _LazyModule({super.key, required this.active, required this.builder});

  final bool active;
  final Widget Function() builder;

  @override
  State<_LazyModule> createState() => _LazyModuleState();
}

class _LazyModuleState extends State<_LazyModule> {
  late bool _activated = widget.active;

  @override
  void didUpdateWidget(covariant _LazyModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _activated = true;
  }

  @override
  Widget build(BuildContext context) {
    return _activated ? widget.builder() : const SizedBox.shrink();
  }
}

class _AppNavigationDrawer extends StatelessWidget {
  const _AppNavigationDrawer({
    required this.order,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<String> order;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final drawerWidth = (MediaQuery.sizeOf(context).width - 40)
        .clamp(240.0, 272.0)
        .toDouble();
    return SizedBox(
      key: const ValueKey('app-navigation-drawer'),
      width: drawerWidth,
      child: Material(
        color: colors.card,
        child: SafeArea(
          right: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 76,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/logo_v2_01.png',
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'EasyNode',
                            maxLines: 1,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.border,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: order.length,
                    itemBuilder: (context, index) {
                      final key = order[index];
                      final item = _moduleItem(context, key);
                      return _DrawerNavigationItem(
                        icon: item.icon,
                        label: item.label,
                        selected: key == selectedKey,
                        onTap: () => onSelected(key),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerNavigationItem extends StatelessWidget {
  const _DrawerNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.primary : colors.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? colors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 8,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 3,
                        height: selected ? 20 : 0,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconTheme(
                    data: IconThemeData(color: foreground, size: 21),
                    child: icon,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
    required this.order,
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final List<String> order;
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return NavigationRailTheme(
      data: NavigationRailTheme.of(context).copyWith(
        backgroundColor: colors.card,
        indicatorColor: colors.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        selectedIconTheme: IconThemeData(color: colors.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: colors.muted, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: NavigationRail(
        scrollable: true,
        extended: extended,
        minWidth: 72,
        minExtendedWidth: 208,
        groupAlignment: -1,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: extended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.selected,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
          child: extended
              ? SizedBox(
                  width: 176,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/logo_v2_01.png',
                          width: 32,
                          height: 32,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'EasyNode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/logo_v2_01.png',
                    width: 32,
                    height: 32,
                  ),
                ),
        ),
        destinations: order.map((key) {
          final item = _moduleItem(context, key);
          return NavigationRailDestination(
            icon: item.icon,
            label: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}

({Widget icon, String label}) _moduleItem(BuildContext context, String key) {
  final l = AppLocalizations.of(context);
  return switch (key) {
    'settings' => (
      icon: const Icon(Icons.settings_outlined),
      label: l.tr('tabs.settings'),
    ),
    'scheduledTasks' => (
      icon: const Icon(Icons.schedule_outlined),
      label: l.tr('tabs.scheduledTasks'),
    ),
    'scripts' => (
      icon: const Icon(Icons.article_outlined),
      label: l.tr('tabs.scripts'),
    ),
    'servers' => (
      icon: const Icon(Icons.monitor_outlined),
      label: l.tr('tabs.servers'),
    ),
    'sftp' => (
      icon: const Icon(Icons.folder_outlined),
      label: l.tr('tabs.sftp'),
    ),
    'docker' => (icon: const DockerIcon(), label: l.tr('tabs.docker')),
    _ => (icon: const Icon(Icons.help_outline), label: key),
  };
}
