import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shell/sftp_session_manager.dart';
import '../features/terminal/server_status_monitor_manager.dart';
import '../features/terminal/terminal_session_manager.dart';
import 'terminal_settings_notifier.dart';

/// Single TerminalSessionManager for the whole app. Used to be passed
/// through constructors; now lives here so any page can reach it. Disposed
/// alongside the ProviderScope at app teardown.
final terminalSessionManagerProvider = Provider<TerminalSessionManager>((ref) {
  final manager = TerminalSessionManager(
    statusMonitorManager: ref.watch(serverStatusMonitorManagerProvider),
    shouldAutoStartStatusMonitor: () =>
        ref.read(terminalSettingsProvider).autoServerStatus,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final serverStatusMonitorManagerProvider = Provider<ServerStatusMonitorManager>(
  (ref) {
    final manager = ServerStatusMonitorManager();
    ref.onDispose(manager.dispose);
    return manager;
  },
);

final sftpSessionManagerProvider = Provider<SftpSessionManager>((ref) {
  final manager = SftpSessionManager();
  ref.onDispose(manager.dispose);
  return manager;
});
