import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy preferences normalize independently and persist full access',
    () async {
      SharedPreferences.setMockInitialValues({
        'agent.mode': 'review',
        'desktop.terminal.agent.mode': 'authorized',
      });
      final storage = AppStorage(await SharedPreferences.getInstance());
      expect(storage.agentMode, 'assist');
      expect(storage.terminalAgentMode, 'authorized');
      await storage.setAgentMode('full_access');
      final restored = AppStorage(await SharedPreferences.getInstance());
      expect(restored.agentMode, 'full_access');
      expect(restored.terminalAgentMode, 'authorized');
      await storage.setTerminalAgentMode('invalid');
      expect(storage.terminalAgentMode, 'assist');
    },
  );

  test(
    'history and explicit host ceilings normalize without raising limits',
    () {
      for (final mode in ['assist', 'authorized', 'full_access']) {
        expect(AgentSession.fromJson({'permission': mode}).permission, mode);
        expect(ServerAiPolicy.fromJson({'maxMode': mode}).maxMode, mode);
      }
      for (final mode in ['review', 'invalid']) {
        expect(
          AgentSession.fromJson({'permission': mode}).permission,
          'assist',
        );
        expect(ServerAiPolicy.fromJson({'maxMode': mode}).maxMode, 'assist');
      }
      expect(AgentSession.fromJson({}).permission, 'assist');
      expect(ServerAiPolicy.fromJson({}).maxMode, 'full_access');
    },
  );
}
