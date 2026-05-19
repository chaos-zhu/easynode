import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/terminal_providers.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/terminal_shell_page.dart';
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
  String _query = '';
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(hostListProvider.notifier).refresh();

  Future<void> _connect(ServerModel server) async {
    if (!server.canConnect) return;
    final manager = ref.read(terminalSessionManagerProvider);

    final existing = manager.firstForHost(server.id);
    if (existing != null) {
      manager.setActive(existing.id);
      _openShell();
      return;
    }

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
    final manager = ref.watch(terminalSessionManagerProvider);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(l.tr('servers.title')),
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
        onRefresh: _refresh,
        child: AnimatedBuilder(
          animation: manager,
          builder: (context, _) => _buildBody(hostsAsync, manager),
        ),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<ServerModel>> hostsAsync,
    Object manager,
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
        final filtered = _filteredServers(servers);
        final sessions = ref.read(terminalSessionManagerProvider).sessions.length;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
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
            if (servers.isEmpty)
              _MessageState(message: l.tr('servers.emptyHint'))
            else if (filtered.isEmpty)
              _MessageState(message: l.tr('servers.emptyFiltered'))
            else
              for (final server in filtered)
                _ServerCard(server: server, state: this),
          ],
        );
      },
    );
  }

  List<ServerModel> _filteredServers(List<ServerModel> servers) {
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

  String _actionText(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (!server.isConfig) return l.tr('servers.notConfigured');
    return l.tr('common.connect');
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
                const Icon(Icons.layers),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? l.tr('servers.activeTerminalsOne')
                        : l.trf('servers.activeTerminalsMany', [count]),
                  ),
                ),
                const Icon(Icons.chevron_right),
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
  const _ServerCard({required this.server, required this.state});

  final ServerModel server;
  final _ServersTabState state;

  @override
  Widget build(BuildContext context) {
    final connecting = state._connectingIds.contains(server.id);
    final l = AppLocalizations.of(context);
    return Card(
      key: Key('server-${server.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(server.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(server.connectionLabel, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _InfoChip(
                  label: server.authType.isEmpty
                      ? l.tr('servers.authFallback')
                      : server.authType,
                ),
                if (server.group.isNotEmpty) _InfoChip(label: server.group),
              ],
            ),
          ],
        ),
        trailing: connecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: server.canConnect
                    ? () => state._connect(server)
                    : null,
                child: Text(state._actionText(server)),
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
