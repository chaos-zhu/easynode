import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_notifier.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../servers/server_model.dart';
import '../terminal/ssh_connection_config.dart';
import 'rdp_engine.dart';
import 'rdp_repository.dart';

final desktopRdpWorkspaceProvider = Provider.autoDispose<DesktopRdpWorkspace>((
  ref,
) {
  ref.watch(authProvider.select((a) => a.session));
  final workspace = DesktopRdpWorkspace(
    fetch: (id) => ref.read(rdpRepositoryProvider).fetch(id),
    onConnected: (server) async {
      await ref.read(apiClientProvider).postJson('/host-last-connect', {
        'id': server.id,
      });
      ref.invalidate(desktopServerCatalogProvider);
    },
  );
  ref.onDispose(workspace.dispose);
  return workspace;
});

enum RdpWindowStatus { connecting, connected, disconnected, error }

class DesktopRdpConnection {
  DesktopRdpConnection(this.server, this.options);
  final ServerModel server;
  final RdpOptions options;
  RdpWindowStatus status = RdpWindowStatus.connecting;
  String? error;
  RdpEngineWindow? window;
  bool closed = false;
}

/// Owned by the authenticated desktop shell, not the selected page: switching
/// menus keeps windows alive, signing out or closing EasyNode closes them.
class DesktopRdpWorkspace extends ChangeNotifier {
  DesktopRdpWorkspace({
    required this.fetch,
    this.onConnected,
    RdpEngine? engine,
  }) : engine = engine ?? RdpEngine();
  final Future<SshConnectionConfig> Function(String) fetch;
  final RdpEngine engine;
  final Future<void> Function(ServerModel)? onConnected;
  final _connections = <DesktopRdpConnection>[];
  List<DesktopRdpConnection> get connections => List.unmodifiable(_connections);
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open(
    ServerModel server, {
    RdpOptions options = const RdpOptions(),
  }) async {
    final existing = _connections
        .where((c) => c.server.id == server.id)
        .firstOrNull;
    if (existing != null) {
      if (existing.status == RdpWindowStatus.connecting) return;
      if (existing.status == RdpWindowStatus.connected) {
        try {
          await existing.window?.focus();
        } catch (_) {
          /* Exit is reported by done. */
        }
        return;
      }
      await close(existing);
    }
    if (_disposed) return;
    final entry = DesktopRdpConnection(server, options);
    _connections.add(entry);
    _changed();
    try {
      final config = await fetch(server.id);
      if (entry.closed) return;
      final window = await engine.open(config, options);
      entry.window = window;
      if (entry.closed) {
        await window.close();
        return;
      }
      unawaited(
        window.done.then((code) {
          if (entry.closed) return;
          entry.status = code == 0
              ? RdpWindowStatus.disconnected
              : RdpWindowStatus.error;
          entry.error = code == 0 ? null : 'RDP connection ended (code $code)';
          _changed();
        }),
      );
      if (await window.connected && !entry.closed) {
        entry.status = RdpWindowStatus.connected;
        _changed();
        unawaited(onConnected?.call(server).catchError((Object _) {}));
      }
    } catch (e) {
      if (entry.closed) return;
      entry.status = RdpWindowStatus.error;
      entry.error = '$e';
      _changed();
    }
  }

  Future<void> close(DesktopRdpConnection entry) async {
    entry.closed = true;
    _connections.remove(entry);
    _changed();
    await entry.window?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _connections) {
      entry.closed = true;
      entry.window?.terminate();
    }
    _connections.clear();
    super.dispose();
  }
}
