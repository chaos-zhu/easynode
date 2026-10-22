import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
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
  bool _terminalMounted = false;
  bool _fullscreen = false;

  void _select(_DesktopModule module) {
    setState(() {
      _selected = module;
      if (module == _DesktopModule.terminal) _terminalMounted = true;
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

  void _connect(ServerModel server) {
    _select(_DesktopModule.terminal);
    ref.read(desktopTerminalWorkspaceProvider).open(server);
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
                                    Tooltip(
                                      message: l.tr('desktop.comingSoon'),
                                      child: MenuItemButton(
                                        key: const Key('desktop-ai'),
                                        trailingIcon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                        child: Text(l.tr('desktop.showAI')),
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
                                        setState(
                                          () => _selected =
                                              _DesktopModule.settings,
                                        );
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
                  index: _selected == _DesktopModule.servers
                      ? 0
                      : _selected == _DesktopModule.terminal
                      ? 1
                      : 2,
                  children: [
                    ExcludeFocus(
                      excluding: _selected != _DesktopModule.servers,
                      child: DesktopServersPage(onConnect: _connect),
                    ),
                    if (_terminalMounted)
                      ExcludeFocus(
                        excluding: _selected != _DesktopModule.terminal,
                        child: TickerMode(
                          enabled: _selected == _DesktopModule.terminal,
                          child: DesktopTerminalPage(
                            onFullscreenChanged: (value) {
                              if (mounted) setState(() => _fullscreen = value);
                            },
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.tr(_selected.labelKey),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: colors.text),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _selected.icon,
                                    size: 48,
                                    color: colors.softMuted,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    l.tr('desktop.comingSoon'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
