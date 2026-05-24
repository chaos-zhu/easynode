import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/group_list_notifier.dart';
import '../../state/server_data_refresh.dart';
import '../../state/terminal_providers.dart';
import 'server_form_page.dart';
import 'server_group_model.dart';
import '../shell/tab_header.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/terminal_shell_page.dart';
import '../terminal/terminal_session_manager.dart';
import 'server_model.dart';

/// First bottom-nav tab — server list + connect action. Was a top-level
/// page that built its own ServerRepository / TerminalSessionManager; now
/// it sources both from providers so state stays consistent across tabs.
class ServersTab extends ConsumerStatefulWidget {
  const ServersTab({super.key});

  @override
  ConsumerState<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<ServersTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _connectingIds = {};
  final Set<String> _expandedServerIds = {};
  String? _selectedGroupId;
  String _query = '';
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await refreshServerSharedData(ref);
  }

  Future<void> _connect(ServerModel server) async {
    if (server.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).tr('servers.windowsUnsupported'),
          ),
        ),
      );
      return;
    }
    if (!server.canConnect) return;
    final manager = ref.read(terminalSessionManagerProvider);

    setState(() => _connectingIds.add(server.id));
    final SshConnectionConfig config;
    try {
      config = await ref
          .read(serverRepositoryProvider)
          .fetchSshConfig(server.id);
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).trf('servers.fetchSshFailed', [error.toString()]),
          ),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _connectingIds.remove(server.id));
    }

    if (!mounted) return;
    await manager.openSession(config);
    if (!mounted) return;
    _openShell();
  }

  void _openShell() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TerminalShellPage()));
  }

  Future<void> _openForm({ServerModel? server}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ServerFormPage(server: server)),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete(ServerModel server) async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var deleting = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> delete() async {
              setDialogState(() => deleting = true);
              try {
                final message = await ref
                    .read(serverRepositoryProvider)
                    .deleteHost(server.id);
                if (!mounted) return;
                setState(() => _expandedServerIds.remove(server.id));
                await _refresh();
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } catch (error) {
                if (!mounted) return;
                if (error is UnauthorizedFailure) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  await ref.read(authProvider.notifier).signOut();
                  return;
                }
                if (dialogContext.mounted) {
                  setDialogState(() => deleting = false);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l.trf('servers.deleteFailed', [error.toString()]),
                    ),
                  ),
                );
              }
            }

            return PopScope(
              canPop: !deleting,
              child: AlertDialog(
                title: Text(l.tr('servers.deleteConfirmTitle')),
                content: Text(
                  l.trf('servers.deleteConfirmBody', [server.displayName]),
                ),
                actions: [
                  TextButton(
                    onPressed: deleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: Text(l.tr('common.cancel')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppPalette.danger.withValues(
                        alpha: 0.62,
                      ),
                      disabledForegroundColor: Colors.white,
                    ),
                    onPressed: deleting ? null : delete,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: deleting
                          ? Row(
                              key: const ValueKey('deleting'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(l.tr('common.delete')),
                              ],
                            )
                          : Text(
                              l.tr('common.delete'),
                              key: const ValueKey('delete-label'),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  Future<void> _confirmCloseAllTerminals() async {
    final manager = ref.read(terminalSessionManagerProvider);
    final count = manager.sessions.length;
    if (count == 0) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('servers.closeAllTitle')),
        content: Text(
          count == 1
              ? l.tr('servers.closeAllBodyOne')
              : l.trf('servers.closeAllBodyMany', [count]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.tr('common.closeAll')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await manager.closeAll();
  }

  @override
  Widget build(BuildContext context) {
    // Logout from UnauthorizedFailure inside refresh is handled by the
    // notifier; we just need to redraw on host-list state changes.
    final hostsAsync = ref.watch(hostListProvider);
    final groupsAsync = ref.watch(groupListProvider);
    final manager = ref.watch(terminalSessionManagerProvider);

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      body: RefreshIndicator(
        color: AppPalette.primary,
        backgroundColor: AppPalette.card,
        displacement: 30,
        edgeOffset: 6,
        strokeWidth: 2,
        onRefresh: _refresh,
        child: AnimatedBuilder(
          animation: manager,
          builder: (context, _) => _buildBody(hostsAsync, groupsAsync, manager),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l) {
    return TabHeader(
      title: l.tr('tabs.servers'),
      actions: [
        _HeaderIconButton(
          tooltip: _searchVisible
              ? l.tr('common.closeSearch')
              : l.tr('common.search'),
          icon: _searchVisible ? Icons.close : Icons.search,
          onPressed: _toggleSearch,
        ),
        const SizedBox(width: 4),
        _HeaderIconButton(
          tooltip: l.tr('servers.addServer'),
          icon: Icons.add,
          onPressed: () => _openForm(),
        ),
      ],
    );
  }

  Widget _buildBody(
    AsyncValue<List<ServerModel>> hostsAsync,
    AsyncValue<List<ServerGroupModel>> groupsAsync,
    TerminalSessionManager manager,
  ) {
    final l = AppLocalizations.of(context);
    return hostsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        if (error is UnauthorizedFailure) {
          // signOut already triggered by the notifier; show nothing useful
          // for the brief moment before AppRoot rebuilds to LoginPage.
          return const SizedBox.shrink();
        }
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 56),
            Center(child: Text(error.toString(), textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(l.tr('common.retry')),
              ),
            ),
          ],
        );
      },
      data: (servers) {
        final groups = groupsAsync.valueOrNull ?? const <ServerGroupModel>[];
        final searched = _searchedServers(servers, groups);
        final effectiveGroupId = _effectiveSelectedGroupId(groups);
        final filtered = _filterByGroup(searched, effectiveGroupId);
        final sessions = manager.sessions.length;
        return Column(
          children: [
            _buildHeader(l),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActiveTerminalBanner(
                    count: sessions,
                    onTap: _openShell,
                    onCloseAll: _confirmCloseAllTerminals,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _searchVisible
                          ? Padding(
                              key: const ValueKey('search-field'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _searchCtrl,
                                  autofocus: true,
                                  cursorColor: AppPalette.primary,
                                  style: const TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 14,
                                  ),
                                  decoration: _searchFieldDecoration(
                                    hintText: l.tr('servers.searchHint'),
                                  ),
                                  onChanged: (value) => setState(
                                    () => _query = value.trim().toLowerCase(),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('search-empty'),
                              width: double.infinity,
                            ),
                    ),
                  ),
                  _ServerGroupFilter(
                    groups: groups,
                    servers: searched,
                    selectedGroupId: effectiveGroupId,
                    onSelected: (groupId) => setState(() {
                      _selectedGroupId = groupId;
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: [
                  if (servers.isEmpty)
                    _MessageState(message: l.tr('servers.emptyHint'))
                  else if (filtered.isEmpty)
                    _MessageState(message: l.tr('servers.emptyFiltered'))
                  else
                    for (final server in filtered)
                      _ServerCard(
                        server: server,
                        state: this,
                        groupName: _groupDisplayName(server, groups),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<ServerModel> _searchedServers(
    List<ServerModel> servers,
    List<ServerGroupModel> groups,
  ) {
    if (_query.isEmpty) return servers;
    return servers
        .where((server) {
          final groupName = _groupDisplayName(server, groups);
          final haystack = [
            server.name,
            server.host,
            server.username,
            server.group,
            groupName,
            ...server.tag,
          ].join(' ').toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }

  String? _effectiveSelectedGroupId(List<ServerGroupModel> groups) {
    if (_selectedGroupId == null) return null;
    if (groups.any((group) => group.id == _selectedGroupId)) {
      return _selectedGroupId;
    }
    return null;
  }

  List<ServerModel> _filterByGroup(List<ServerModel> servers, String? groupId) {
    if (groupId == null) return servers;
    return servers
        .where((server) => _normalizedGroupId(server.group) == groupId)
        .toList(growable: false);
  }

  static String _normalizedGroupId(String groupId) {
    return groupId.isEmpty ? 'default' : groupId;
  }

  String _groupDisplayName(ServerModel server, List<ServerGroupModel> groups) {
    final groupId = _normalizedGroupId(server.group);
    for (final group in groups) {
      if (group.id == groupId) return group.displayName;
    }
    return server.group;
  }

  String _actionText(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (!server.isConfig) return l.tr('servers.notConfigured');
    return l.tr('common.connect');
  }

  String _authTypeLabel(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (server.authType.isEmpty) return l.tr('servers.authFallback');
    if (server.authType == 'password') return l.tr('servers.auth.password');
    return l.tr('servers.auth.privateKey');
  }
}

class _ServerGroupFilter extends StatelessWidget {
  const _ServerGroupFilter({
    required this.groups,
    required this.servers,
    required this.selectedGroupId,
    required this.onSelected,
  });

  final List<ServerGroupModel> groups;
  final List<ServerModel> servers;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final counts = <String, int>{for (final group in groups) group.id: 0};
    for (final server in servers) {
      final groupId = _ServersTabState._normalizedGroupId(server.group);
      if (counts.containsKey(groupId)) {
        counts[groupId] = counts[groupId]! + 1;
      } else if (counts.containsKey('default')) {
        counts['default'] = counts['default']! + 1;
      }
    }
    final visibleGroups = groups
        .where((group) => (counts[group.id] ?? 0) > 0)
        .toList(growable: false);
    if (visibleGroups.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: visibleGroups.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _GroupPill(
              label: l.tr('common.all'),
              count: servers.length,
              selected: selectedGroupId == null,
              onTap: () => onSelected(null),
            );
          }
          final group = visibleGroups[index - 1];
          return _GroupPill(
            label: group.displayName,
            count: counts[group.id] ?? 0,
            selected: selectedGroupId == group.id,
            onTap: () => onSelected(group.id),
          );
        },
      ),
    );
  }
}

class _GroupPill extends StatelessWidget {
  const _GroupPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppPalette.primary : Colors.transparent;
    final foreground = selected ? AppPalette.card : AppPalette.muted;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? BorderSide.none
            : const BorderSide(color: AppPalette.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '$label $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveTerminalBanner extends StatelessWidget {
  const _ActiveTerminalBanner({
    required this.count,
    required this.onTap,
    required this.onCloseAll,
  });

  final int count;
  final VoidCallback onTap;
  final VoidCallback onCloseAll;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.banner,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: AppPalette.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? l.tr('servers.activeTerminalsOne')
                        : l.trf('servers.activeTerminalsMany', [count]),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppPalette.primary,
                ),
                const SizedBox(width: 4),
                InkResponse(
                  onTap: onCloseAll,
                  radius: 16,
                  child: Tooltip(
                    message: l.tr('servers.closeAllTooltip'),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: AppPalette.softMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.state,
    required this.groupName,
  });

  final ServerModel server;
  final _ServersTabState state;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    final connecting = state._connectingIds.contains(server.id);
    final expanded = state._expandedServerIds.contains(server.id);
    final l = AppLocalizations.of(context);
    final proxyLabel = switch (server.proxyType) {
      'proxyServer' => l.tr('servers.proxy.proxyServerShort'),
      'jumpHosts' => l.tr('servers.proxy.jumpHostsShort'),
      _ => '-',
    };
    return Container(
      key: Key('server-${server.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expanded ? AppPalette.strongBorder : AppPalette.border,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: AppPalette.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, expanded ? 16 : 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ServerOsIcon(enabled: server.canConnect),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => state._openForm(server: server),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              server.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppPalette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              server.connectionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppPalette.softMuted,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconPillButton(
                    tooltip: expanded ? 'Collapse' : 'Expand',
                    icon: expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    highlighted: expanded,
                    onTap: () {
                      state.setState(() {
                        if (expanded) {
                          state._expandedServerIds.remove(server.id);
                        } else {
                          state._expandedServerIds.add(server.id);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (groupName.isNotEmpty) _InfoChip(label: groupName),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ConnectButton(
                    connecting: connecting,
                    label: state._actionText(server),
                    enabled: server.canConnect || server.isWindows,
                    onPressed: () => state._connect(server),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Column(
                  children: [
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppPalette.border),
                    const SizedBox(height: 12),
                    _ServerDetailRow(
                      icon: Icons.tag_outlined,
                      label: l.tr('servers.field.index'),
                      value: '#${server.index}',
                    ),
                    _ServerDetailRow(
                      icon: Icons.folder_outlined,
                      label: l.tr('servers.field.group'),
                      value: groupName.isEmpty ? '-' : groupName,
                    ),
                    _ServerDetailRow(
                      icon: Icons.sell_outlined,
                      label: l.tr('servers.field.tags'),
                      value: server.tag.isEmpty ? '-' : server.tag.join(', '),
                    ),
                    _ServerDetailRow(
                      icon: Icons.key_outlined,
                      label: l.tr('servers.field.authType'),
                      value: state._authTypeLabel(server),
                    ),
                    _ServerDetailRow(
                      icon: Icons.hub_outlined,
                      label: l.tr('servers.field.proxyType'),
                      value: proxyLabel,
                      emphasized:
                          server.proxyType != 'none' &&
                          server.proxyType.isNotEmpty,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SecondaryActionButton(
                            icon: Icons.delete_outline,
                            label: l.tr('common.delete'),
                            destructive: true,
                            onTap: () => state._confirmDelete(server),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SecondaryActionButton(
                            icon: Icons.edit_outlined,
                            label: l.tr('servers.editServer'),
                            onTap: () => state._openForm(server: server),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 22,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: AppPalette.muted, size: 22),
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({
    required this.tooltip,
    required this.icon,
    required this.highlighted,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted ? AppPalette.banner : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 20,
              color: highlighted
                  ? AppPalette.primary
                  : AppPalette.softMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerOsIcon extends StatelessWidget {
  const _ServerOsIcon({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? AppPalette.banner : AppPalette.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.monitor_outlined,
        size: 22,
        color: enabled ? AppPalette.primary : AppPalette.muted,
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connecting,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final bool connecting;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: connecting
            ? const SizedBox(
                key: ValueKey('connecting'),
                width: 82,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppPalette.primary,
                    ),
                  ),
                ),
              )
            : Material(
                key: const ValueKey('connect-button'),
                color: enabled ? AppPalette.primary : AppPalette.border,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: enabled ? onPressed : null,
                  child: SizedBox(
                    height: 34,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            enabled
                                ? Icons.play_arrow_rounded
                                : Icons.lock_outline,
                            size: 17,
                            color: enabled
                                ? AppPalette.card
                                : AppPalette.muted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: enabled
                                  ? AppPalette.card
                                  : AppPalette.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.banner,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ServerDetailRow extends StatelessWidget {
  const _ServerDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Icon(icon, size: 15, color: AppPalette.softMuted),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppPalette.softMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: emphasized
                    ? AppPalette.primary
                    : AppPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive
        ? AppPalette.danger
        : AppPalette.muted;
    final background = destructive
        ? AppPalette.dangerSoft
        : AppPalette.chip;
    final border = destructive
        ? AppPalette.dangerBorder
        : AppPalette.border;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppPalette.muted),
        ),
      ),
    );
  }
}

InputDecoration _searchFieldDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    filled: true,
    fillColor: AppPalette.card,
    prefixIcon: const Icon(Icons.search, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    hintStyle: const TextStyle(color: AppPalette.softMuted, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.border),
    ),
  );
}
