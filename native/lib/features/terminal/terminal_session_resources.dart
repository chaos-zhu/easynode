import '../docker/docker_session_manager.dart';
import '../shell/sftp_session_manager.dart';

/// Owns auxiliary connections opened from terminal pages. These connections
/// are deliberately separate from the managers used by the bottom-nav tabs.
class TerminalSessionResources {
  final Map<String, SftpSessionManager> _sftpManagers = {};
  final Map<String, DockerSessionManager> _dockerManagers = {};

  SftpSessionManager sftpForHost(String hostId) =>
      _sftpManagers.putIfAbsent(hostId, SftpSessionManager.new);

  DockerSessionManager dockerForHost(String hostId) =>
      _dockerManagers.putIfAbsent(hostId, DockerSessionManager.new);

  Future<void> disposeHost(String hostId) async {
    final sftpManager = _sftpManagers.remove(hostId);
    await sftpManager?.disconnectAll();
    sftpManager?.dispose();

    final dockerManager = _dockerManagers.remove(hostId);
    dockerManager?.dispose();
  }

  void dispose() {
    for (final manager in _sftpManagers.values) {
      manager.dispose();
    }
    for (final manager in _dockerManagers.values) {
      manager.dispose();
    }
    _sftpManagers.clear();
    _dockerManagers.clear();
  }
}
