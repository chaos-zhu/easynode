import 'package:flutter/material.dart';

import '../../core/api/api_result.dart';
import '../auth/auth_session.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/terminal_session_manager.dart';
import '../terminal/terminal_shell_page.dart';
import 'server_model.dart';
import 'server_repository.dart';

class ServerListPage extends StatefulWidget {
  const ServerListPage({
    super.key,
    required this.repository,
    required this.session,
    required this.terminalSessionManager,
    required this.onLogout,
  });

  final ServerRepository repository;
  final AuthSession session;
  final TerminalSessionManager terminalSessionManager;
  final VoidCallback onLogout;

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _connectingIds = {};
  List<ServerModel> _servers = const [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await widget.repository.fetchHosts();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        widget.onLogout();
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connect(ServerModel server) async {
    if (!server.canConnect) return;

    final existing = widget.terminalSessionManager.firstForHost(server.id);
    if (existing != null) {
      widget.terminalSessionManager.setActive(existing.id);
      _openShell();
      return;
    }

    setState(() => _connectingIds.add(server.id));
    final SshConnectionConfig config;
    try {
      config = await widget.repository.fetchSshConfig(server.id);
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        widget.onLogout();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get SSH config: $error')),
      );
      return;
    } finally {
      if (mounted) setState(() => _connectingIds.remove(server.id));
    }

    if (!mounted) return;
    await widget.terminalSessionManager.openSession(config);
    if (!mounted) return;
    _openShell();
  }

  void _openShell() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalShellPage(
          manager: widget.terminalSessionManager,
          repository: widget.repository,
          initialServers: _servers,
          onSessionExpired: widget.onLogout,
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('This will clear the saved login session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AnimatedBuilder(
          animation: widget.terminalSessionManager,
          builder: (context, _) => _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 56),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
          const SizedBox(height: 8),
          Center(
            child: TextButton(onPressed: _refresh, child: const Text('Retry')),
          ),
        ],
      );
    }

    final filtered = _filteredServers();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        _ActiveTerminalBanner(
          count: widget.terminalSessionManager.sessions.length,
          onTap: _openShell,
        ),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name, host, user, tag, or group',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 8),
        if (_servers.isEmpty)
          const _MessageState(
            message:
                'No servers yet. Pull to refresh after adding hosts on web.',
          )
        else if (filtered.isEmpty)
          const _MessageState(message: 'No matching servers.')
        else
          for (final server in filtered)
            _ServerCard(server: server, state: this),
      ],
    );
  }

  List<ServerModel> _filteredServers() {
    if (_query.isEmpty) return _servers;
    return _servers
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
    if (!server.isConfig) return 'Not configured';
    if (server.expired) return 'Expired';
    return widget.terminalSessionManager.firstForHost(server.id) == null
        ? 'Connect'
        : 'Enter';
  }
}

class _ActiveTerminalBanner extends StatelessWidget {
  const _ActiveTerminalBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer,
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
                  child: Text('$count active terminal${count == 1 ? '' : 's'}'),
                ),
                const Icon(Icons.chevron_right),
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
  final _ServerListPageState state;

  @override
  Widget build(BuildContext context) {
    final connecting = state._connectingIds.contains(server.id);
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
                  label: server.authType.isEmpty ? 'auth' : server.authType,
                ),
                if (server.group.isNotEmpty) _InfoChip(label: server.group),
                if (server.expired)
                  const _InfoChip(label: 'expired', destructive: true),
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
  const _InfoChip({required this.label, this.destructive = false});

  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: destructive ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: destructive
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
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
