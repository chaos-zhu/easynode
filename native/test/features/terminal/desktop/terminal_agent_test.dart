import 'dart:async';

import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/features/ai_agent/agent_controller.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_repository.dart';
import 'package:easynode_native/features/ai_agent/agent_socket_client.dart';
import 'package:easynode_native/features/ai_agent/terminal_agent_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Socket implements AgentSocketClient {
  final eventBus = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final connectionsBus = StreamController<AgentConnectionStatus>.broadcast();
  final errorsBus = StreamController<String>.broadcast();
  final runs = <Map<String, dynamic>>[],
      results = <Map<String, dynamic>>[],
      progress = <Map<String, dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get events => eventBus.stream;
  @override
  Stream<AgentConnectionStatus> get connections => connectionsBus.stream;
  @override
  Stream<String> get errors => errorsBus.stream;
  @override
  void runTerminal({
    required String input,
    required String modelId,
    required String permission,
    required String hostId,
    required String hostName,
    String? sessionId,
  }) {
    runs.add({
      'input': input,
      'hostId': hostId,
      'hostName': hostName,
      'sessionId': sessionId,
      'permission': permission,
    });
  }

  @override
  void run({
    required String input,
    required String modelId,
    required String permission,
    String? sessionId,
  }) => throw StateError('terminal must not use ops run');
  @override
  void terminalResult(String id, Map<String, dynamic> result) =>
      results.add({'id': id, ...result});
  @override
  void terminalProgress(String id, Map<String, dynamic> value) =>
      progress.add({'id': id, ...value});
  @override
  void stop() {}
  @override
  void dispose() {
    unawaited(eventBus.close());
    unawaited(connectionsBus.close());
    unawaited(errorsBus.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements AgentRepository {
  String? listedHost, clearedHost;
  AgentSession session = AgentSession.fromJson({
    '_id': 'history',
    'scope': 'terminal',
    'hostId': 'host-one',
  });
  @override
  Future<List<AgentSessionSummary>> getTerminalSessions(String id) async {
    listedHost = id;
    return [];
  }

  @override
  Future<void> clearTerminalSessions(String id) async {
    clearedHost = id;
  }

  @override
  Future<List<AgentSessionSummary>> getSessions() =>
      throw StateError('terminal must not read ops history');
  @override
  Future<AgentSession> getSession(String id) async => session;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Socket socket;
  late _Repository repository;
  late AppStorage storage;
  late AgentState state;
  late AgentController controller;
  late List<String> executed;
  late bool connected;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = AppStorage(await SharedPreferences.getInstance());
    await storage.setAgentModel('ops-model');
    await storage.setAgentMode('assist');
    socket = _Socket();
    repository = _Repository();
    executed = [];
    connected = true;
    state = const AgentState(
      connection: AgentConnectionStatus.connected,
      modelId: 'test-model',
    );
    controller = AgentController(
      repository: repository,
      socket: socket,
      storage: storage,
      read: () => state,
      emit: (next) => state = next,
      terminalBinding: TerminalAgentBinding(
        hostId: 'host-one',
        hostName: 'Production',
        isConnected: () => connected,
        execute: (command, id, progress) async {
          executed.add(command);
          progress({'output': 'partial'});
          return {'ok': true, 'output': 'done', 'exitCode': 0};
        },
        cancel: (id) async => {'ok': true, 'exitCode': 130},
      ),
    );
  });
  tearDown(() => controller.dispose());
  test(
    'send uses current terminal target and requires connected local PTY',
    () {
      connected = false;
      expect(controller.send('hello'), 'desktop.terminal.notConnected');
      expect(socket.runs, isEmpty);
      connected = true;
      expect(controller.send('inspect server'), isNull);
      expect(socket.runs.single['hostId'], 'host-one');
      expect(socket.runs.single['hostName'], 'Production');
      expect(state.conversation.running, true);
    },
  );
  test(
    'only matching terminal executes tools and returns progress/results',
    () async {
      socket.eventBus.add({
        'type': 'terminal_command_request',
        'requestId': 'one',
        'hostId': 'host-one',
        'command': 'uname -a',
      });
      await Future<void>.delayed(Duration.zero);
      expect(executed, ['uname -a']);
      expect(socket.progress.single['output'], 'partial');
      expect(socket.results.single['output'], 'done');
      socket.eventBus.add({
        'type': 'terminal_command_request',
        'requestId': 'two',
        'hostId': 'other-host',
        'command': 'rm -rf /',
      });
      await Future<void>.delayed(Duration.zero);
      expect(executed, ['uname -a']);
      expect(socket.results.last['ok'], false);
    },
  );
  test(
    'terminal history is scoped by host and rejects incompatible sessions',
    () async {
      await controller.refreshSessions();
      expect(repository.listedHost, 'host-one');
      await controller.loadSession('history');
      repository.session = AgentSession.fromJson({
        'scope': 'ops',
        'hostId': 'host-one',
      });
      await expectLater(
        controller.loadSession('ops-history'),
        throwsStateError,
      );
      repository.session = AgentSession.fromJson({
        'scope': 'terminal',
        'hostId': 'other-host',
      });
      await expectLater(
        controller.loadSession('other-history'),
        throwsStateError,
      );
      await controller.clearSessions();
      expect(repository.clearedHost, 'host-one');
    },
  );
  test(
    'terminal model/mode preferences do not change mobile ops preferences',
    () async {
      await controller.setModel('terminal-model');
      await controller.setMode('review');
      expect(storage.agentModel, 'ops-model');
      expect(storage.agentMode, 'assist');
      expect(storage.terminalAgentModel, 'terminal-model');
      expect(storage.terminalAgentMode, 'review');
    },
  );
}
