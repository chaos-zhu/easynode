import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/agent_providers.dart';
import '../../../state/auth_notifier.dart';
import '../../../state/storage_providers.dart';
import '../../ai_agent/agent_panel.dart';
import '../../ai_agent/agent_socket_client.dart';
import '../../ai_agent/terminal_agent_binding.dart';
import 'desktop_terminal_workspace.dart';

/// Reuses the complete chat UI with an isolated terminal-scoped controller.
class DesktopTerminalAgent extends StatelessWidget {
  const DesktopTerminalAgent({
    super.key,
    required this.pane,
    required this.workspace,
    required this.onClose,
  });
  final DesktopTerminalPane pane;
  final DesktopTerminalWorkspace workspace;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      agentControllerProvider.overrideWith((ref) {
        final session = ref.watch(authProvider).session!;
        return AgentStateNotifier(
          repository: ref.watch(agentRepositoryProvider),
          socket: AgentSocketClient(
            authSession: session,
            cookieStore: ref.watch(cookieStoreProvider),
            certificateTrust: ref.watch(certificateTrustProvider),
          ),
          storage: ref.watch(appStorageProvider),
          terminalBinding: TerminalAgentBinding(
            hostId: pane.server.id,
            hostName: pane.server.displayName,
            isConnected: () =>
                !pane.closed && pane.status == DesktopTerminalStatus.connected,
            execute: (command, id, progress) =>
                workspace.executeAi(pane, command, id, onProgress: progress),
            cancel: pane.commands.cancel,
          ),
        );
      }),
    ],
    child: Theme(
      data: Theme.of(context).copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(28, 28),
            padding: const EdgeInsets.all(5),
            iconSize: 16,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      child: AgentTerminalActions(
        execute: (command) =>
            workspace.input(pane, '$command\n', synchronize: false),
        child: AgentPanel(
          desktopLayout: true,
          prefill: pane.aiPrefill,
          terminalHostName: pane.server.displayName,
          onClose: onClose,
        ),
      ),
    ),
  );
}
