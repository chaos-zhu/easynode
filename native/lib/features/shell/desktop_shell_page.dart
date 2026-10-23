import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../state/agent_providers.dart';
import '../../state/storage_providers.dart';
import '../batch/desktop_batch_page.dart';
import '../file_transfer/desktop_file_transfer_page.dart';
import '../rdp/desktop_rdp_page.dart';
import '../rdp/desktop_rdp_workspace.dart';
import '../scheduled_tasks/desktop_scheduled_tasks_page.dart';
import '../scripts/desktop_scripts_page.dart';
import '../settings/desktop_credentials_page.dart';
import '../settings/desktop_settings_page.dart';
import '../../l10n/app_localizations.dart';
import '../../state/auth_notifier.dart';
import '../../state/package_info_provider.dart';
import '../../state/theme_mode_notifier.dart';
import '../servers/desktop_servers_page.dart';
import '../servers/server_model.dart';
import '../terminal/desktop/desktop_terminal_page.dart';
import '../terminal/desktop/desktop_terminal_workspace.dart';

/// Desktop navigation mounts only the implemented desktop feature pages.
class DesktopShellPage extends ConsumerStatefulWidget {
  const DesktopShellPage({super.key});

  @override
  ConsumerState<DesktopShellPage> createState() => _DesktopShellPageState();
}

enum _DesktopModule {
  servers(Icons.dns_outlined),
  terminal(Icons.terminal),
  rdp(Icons.desktop_windows_outlined),
  files(Icons.folder_copy_outlined),
  credentials(Icons.key_outlined),
  scripts(Icons.code),
  batch(Icons.playlist_play),
  scheduledTasks(Icons.schedule),
  settings(Icons.settings_outlined);

  const _DesktopModule(this.icon);
  final IconData icon;
  String get labelKey => 'desktop.menu.$name';
}

class _DesktopShellPageState extends ConsumerState<DesktopShellPage> {
  _DesktopModule _selected = _DesktopModule.servers;
  bool _collapsed = false;
  final _visited = <_DesktopModule>{_DesktopModule.servers};
  bool _aiPreferenceBusy = false;
  bool _fullscreen = false;

  void _select(_DesktopModule module) {
    setState(() {
      _selected = module;
      _visited.add(module);
    });
    if (module == _DesktopModule.terminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == _DesktopModule.terminal) {
          ref
              .read(desktopTerminalWorkspaceProvider)
              .activeTab
              ?.activePane
              .focusNode
              .requestFocus();
        }
      });
    }
  }

  void _settings(DesktopSettingsSection section) {
    ref.read(desktopSettingsSectionProvider.notifier).state = section;
    _select(_DesktopModule.settings);
  }

  Future<void> _toggleAssistant() async {
    setState(() => _aiPreferenceBusy = true);
    try {
      final enabled = await ref
          .read(agentRepositoryProvider)
          .setNativeAgentEnabled(!ref.read(nativeAgentEnabledProvider));
      await ref.read(appStorageProvider).setNativeAgentEnabledCache(enabled);
      ref.invalidate(agentSettingsProvider);
    } catch (e) {
      if (mounted) managementNotice(context, managementError(e));
    } finally {
      if (mounted) setState(() => _aiPreferenceBusy = false);
    }
  }

  Widget _page(_DesktopModule module) => switch (module) {
    _DesktopModule.servers => DesktopServersPage(onConnect: _connect),
    _DesktopModule.terminal => DesktopTerminalPage(
      onFullscreenChanged: (value) {
        if (mounted) setState(() => _fullscreen = value);
      },
    ),
    _DesktopModule.files => const DesktopFileTransferPage(),
    _DesktopModule.rdp => const DesktopRdpPage(),
    _DesktopModule.credentials => const DesktopCredentialsPage(),
    _DesktopModule.scripts => const DesktopScriptsPage(),
    _DesktopModule.batch => const DesktopBatchPage(),
    _DesktopModule.scheduledTasks => const DesktopScheduledTasksPage(),
    _DesktopModule.settings => const DesktopSettingsPage(),
  };

  void _connect(ServerModel server) {
    if (server.isWindows) {
      _select(_DesktopModule.rdp);
      ref.read(desktopRdpWorkspaceProvider).open(server);
    } else {
      _select(_DesktopModule.terminal);
      ref.read(desktopTerminalWorkspaceProvider).open(server);
    }
  }

  bool _signingOut = false;
  final _accountMenuController = MenuController();

  Future<void> _logout() async {
    if (_signingOut) return;
    final l = AppLocalizations.of(context);
    setState(() => _signingOut = true);
    try {
      await ref.read(authProvider.notifier).signOutSafely();
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('login.secureStorageFailed'))),
      );
    }
  }

  Future<void> _showVersion() async {
    final l = AppLocalizations.of(context);
    final info = await ref.read(packageInfoProvider.future);
    if (!mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('desktop.versionUpdate')),
        content: Text(l.trf('desktop.currentVersion', ['v${info.version}'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.tr('common.close')),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/chaos-zhu/easynode'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l.tr('login.project')),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTheme() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await ref
          .read(themeModeProvider.notifier)
          .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).tr('desktop.preferenceFailed'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(authProvider).session;
    final colors = context.colors;
    // The authenticated shell owns the workspace, including the first list-to-terminal connection.
    ref.watch(desktopTerminalWorkspaceProvider);
    ref.watch(desktopRdpWorkspaceProvider);
    final aiEnabled = ref.watch(nativeAgentEnabledProvider);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Row(
          children: [
            Offstage(
              offstage: _fullscreen,
              child: ExcludeFocus(
                excluding: _fullscreen,
                child: Container(
                  key: const Key('desktop-sidebar'),
                  width: _collapsed ? 64 : 174,
                  color: colors.card,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          children: [
                            for (final module in _DesktopModule.values)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Tooltip(
                                  message: _collapsed
                                      ? l.tr(module.labelKey)
                                      : '',
                                  child: Material(
                                    color: _selected == module
                                        ? colors.accentSoft
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      key: ValueKey(
                                        'desktop-menu-${module.name}',
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _select(module),
                                      child: Semantics(
                                        selected: _selected == module,
                                        label: _collapsed
                                            ? l.tr(module.labelKey)
                                            : null,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: _collapsed ? 12 : 14,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                module.icon,
                                                size: 20,
                                                color: _selected == module
                                                    ? colors.accent
                                                    : colors.muted,
                                              ),
                                              if (!_collapsed) ...[
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    l.tr(module.labelKey),
                                                    style: TextStyle(
                                                      color: _selected == module
                                                          ? colors.accent
                                                          : colors.text,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: colors.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                        child: MenuAnchor(
                          controller: _accountMenuController,
                          style: MenuStyle(
                            alignment: Alignment.bottomRight,
                            minimumSize: const WidgetStatePropertyAll(
                              Size(200, 0),
                            ),
                            backgroundColor: WidgetStatePropertyAll(
                              colors.card,
                            ),
                            surfaceTintColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            side: WidgetStatePropertyAll(
                              BorderSide(color: colors.border),
                            ),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          menuChildren:
                              <Widget>[
                                    MenuItemButton(
                                      key: const Key('desktop-version'),
                                      onPressed: _showVersion,
                                      trailingIcon: const Icon(
                                        Icons.refresh,
                                        size: 18,
                                      ),
                                      child: Text(
                                        l.tr('desktop.versionUpdate'),
                                      ),
                                    ),
                                    MenuItemButton(
                                      key: const Key('desktop-theme'),
                                      onPressed: _toggleTheme,
                                      trailingIcon: Icon(
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Icons.light_mode_outlined
                                            : Icons.dark_mode_outlined,
                                        size: 18,
                                      ),
                                      child: Text(l.tr('desktop.toggleTheme')),
                                    ),
                                    MenuItemButton(
                                      key: const Key('desktop-ai'),
                                      onPressed: _aiPreferenceBusy
                                          ? null
                                          : _toggleAssistant,
                                      trailingIcon: const Icon(
                                        Icons.smart_toy_outlined,
                                        size: 18,
                                      ),
                                      child: Text(
                                        aiEnabled
                                            ? mx(
                                                context,
                                                '隐藏 AI 助手',
                                                'Hide AI assistant',
                                              )
                                            : l.tr('desktop.showAI'),
                                      ),
                                    ),
                                    MenuItemButton(
                                      key: const Key('desktop-collapse'),
                                      onPressed: () => setState(
                                        () => _collapsed = !_collapsed,
                                      ),
                                      trailingIcon: Icon(
                                        _collapsed
                                            ? Icons.menu_open
                                            : Icons.menu,
                                        size: 18,
                                      ),
                                      child: Text(
                                        l.tr(
                                          _collapsed
                                              ? 'desktop.expandSidebar'
                                              : 'desktop.collapseSidebar',
                                        ),
                                      ),
                                    ),
                                    Divider(height: 9, color: colors.border),
                                    MenuItemButton(
                                      key: const Key('desktop-logout'),
                                      onPressed: _signingOut ? null : _logout,
                                      style: ButtonStyle(
                                        foregroundColor: WidgetStatePropertyAll(
                                          colors.danger,
                                        ),
                                      ),
                                      trailingIcon: const Icon(
                                        Icons.logout,
                                        size: 18,
                                      ),
                                      child: Text(l.tr('settings.logout')),
                                    ),
                                  ]
                                  .map(
                                    (item) => SizedBox(width: 200, child: item),
                                  )
                                  .toList(),
                          builder: (context, controller, child) => Material(
                            color: Colors.transparent,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: session?.username ?? '',
                                    child: InkWell(
                                      key: const Key('desktop-account-menu'),
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: _signingOut
                                          ? null
                                          : () => controller.isOpen
                                                ? controller.close()
                                                : controller.open(),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: _collapsed ? 8 : 14,
                                          vertical: 12,
                                        ),
                                        child: _signingOut
                                            ? const Center(
                                                child: SizedBox.square(
                                                  dimension: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                            : _collapsed
                                            ? Icon(
                                                Icons.person_outline,
                                                size: 18,
                                                color: colors.text,
                                              )
                                            : Text(
                                                session?.username ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: colors.text,
                                                  fontSize: 14,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_collapsed)
                                  Tooltip(
                                    message: l.tr('desktop.plusActivation'),
                                    child: InkWell(
                                      key: const Key('desktop-plus'),
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        controller.close();
                                        _settings(DesktopSettingsSection.plus);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 12,
                                        ),
                                        child: Image.asset(
                                          'assets/plus.png',
                                          width: 34,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                key: const ValueKey('desktop-pages'),
                margin: EdgeInsets.all(_fullscreen ? 0 : 10),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IndexedStack(
                  index: _selected.index,
                  children: [
                    for (final module in _DesktopModule.values)
                      _visited.contains(module)
                          ? ExcludeFocus(
                              excluding: _selected != module,
                              child: TickerMode(
                                enabled: _selected == module,
                                child: _page(module),
                              ),
                            )
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
