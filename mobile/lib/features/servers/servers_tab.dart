import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/group_list_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/terminal_providers.dart';
import 'server_group_model.dart';
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
  String? _selectedGroupId;
  String _query = '';
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(groupListProvider.notifier).refresh(),
      ref.read(hostListProvider.notifier).refresh(),
    ]);
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
      config = await ref.read(serverRepositoryProvider).fetchSshConfig(server.id);
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        await ref.read(authProvider.notifier).signOut();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)
                .trf('servers.fetchSshFailed', [error.toString()]),
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TerminalShellPage()),
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
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                'assets/logo_v2_01.png',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(l.tr('servers.title')),
          ],
        ),
        actions: [
          IconButton(
            tooltip:
                _searchVisible ? l.tr('common.closeSearch') : l.tr('common.search'),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _searchVisible ? Icons.close : Icons.search,
                key: ValueKey<bool>(_searchVisible),
              ),
            ),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: l.tr('servers.addServer'),
            icon: const Icon(Icons.add),
            onPressed: null,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.surface,
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
        final searched = _searchedServers(servers);
        final effectiveGroupId = _effectiveSelectedGroupId(groups);
        final filtered = _filterByGroup(searched, effectiveGroupId);
        final sessions = manager.sessions.length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: _searchVisible
                          ? Padding(
                              key: const ValueKey('search-field'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextField(
                                controller: _searchCtrl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText: l.tr('servers.searchHint'),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (value) => setState(
                                  () => _query = value.trim().toLowerCase(),
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
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<ServerModel> _searchedServers(List<ServerModel> servers) {
    if (_query.isEmpty) return servers;
    return servers
        .where((server) {
          final haystack = [
            server.name,
            server.host,
            server.username,
            server.group,
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

  List<ServerModel> _filterByGroup(
    List<ServerModel> servers,
    String? groupId,
  ) {
    if (groupId == null) return servers;
    return servers
        .where((server) => _normalizedGroupId(server.group) == groupId)
        .toList(growable: false);
  }

  static String _normalizedGroupId(String groupId) {
    return groupId.isEmpty ? 'default' : groupId;
  }

  String _actionText(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (!server.isConfig) return l.tr('servers.notConfigured');
    return l.tr('common.connect');
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
    final colors = Theme.of(context).colorScheme;
    final background = selected ? colors.primary : colors.surface;
    final foreground = selected ? colors.onPrimary : colors.onSurfaceVariant;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
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
                    fontWeight: FontWeight.w800,
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
    final colors = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.layers, color: colors.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? l.tr('servers.activeTerminalsOne')
                        : l.trf('servers.activeTerminalsMany', [count]),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
                const SizedBox(width: 4),
                InkResponse(
                  onTap: onCloseAll,
                  radius: 16,
                  child: Tooltip(
                    message: l.tr('servers.closeAllTooltip'),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: colors.onPrimaryContainer,
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
  });

  final ServerModel server;
  final _ServersTabState state;

  @override
  Widget build(BuildContext context) {
    final connecting = state._connectingIds.contains(server.id);
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final statusColor = server.canConnect
        ? colors.primary
        : colors.onSurfaceVariant;
    final iconAsset = server.isWindows
        ? 'assets/windows.svg'
        : 'assets/linux.svg';
    return Card(
      key: Key('server-${server.id}'),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SvgPicture.asset(
                    iconAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        server.connectionLabel,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                      _InfoChip(
                        label: server.authType.isEmpty
                            ? l.tr('servers.authFallback')
                            : server.authType,
                      ),
                      if (server.group.isNotEmpty)
                        _InfoChip(label: server.group),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: connecting
                        ? const SizedBox(
                            key: ValueKey('connecting'),
                            width: 96,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : FilledButton.icon(
                            key: const ValueKey('connect-button'),
                            onPressed: server.canConnect || server.isWindows
                                ? () => state._connect(server)
                                : null,
                            icon: Icon(
                              server.canConnect
                                  ? Icons.play_arrow
                                  : Icons.lock_outline,
                              size: 18,
                            ),
                            label: Text(state._actionText(server)),
                          ),
                  ),
                ),
              ],
            ),
          ],
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSecondaryContainer,
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
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}
