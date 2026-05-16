import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/terminal_page.dart';
import 'server_model.dart';
import 'server_repository.dart';

/// Server list page. Loads `/api/v1/host-list` on init and supports
/// pull-to-refresh; the connect action requests SSH parameters and pushes
/// the terminal page.
class ServerListPage extends StatefulWidget {
  const ServerListPage({
    super.key,
    required this.repository,
    required this.session,
    required this.onLogout,
  });

  final ServerRepository repository;
  final AuthSession session;
  final VoidCallback onLogout;

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  List<ServerModel> _servers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
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
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connect(ServerModel server) async {
    if (!server.canConnect) return;
    final SshConnectionConfig config;
    try {
      config = await widget.repository.fetchSshConfig(server.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取 SSH 参数失败: $error')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalPage(config: config)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器列表'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
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
        children: [
          const SizedBox(height: 80),
          Center(child: Text(_error!)),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_servers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('暂无服务器，请在 Web 端添加后下拉刷新')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _servers.length,
      separatorBuilder: (context, index) => const Divider(height: 0),
      itemBuilder: (_, index) {
        final s = _servers[index];
        return ListTile(
          key: Key('server-${s.id}'),
          title: Text(s.name.isEmpty ? s.host : s.name),
          subtitle: Text('${s.username}@${s.host}:${s.port}  ·  ${s.authType}'),
          trailing: FilledButton.tonal(
            onPressed: s.canConnect ? () => _connect(s) : null,
            child: Text(s.canConnect ? '连接' : '未配置'),
          ),
        );
      },
    );
  }
}
