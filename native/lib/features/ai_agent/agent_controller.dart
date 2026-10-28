import 'dart:async';

import '../../core/ai/agent_mode.dart';

import '../../core/storage/app_storage.dart';
import 'agent_models.dart';
import 'terminal_agent_binding.dart';
import 'panel_catalog_refresh.dart';
import 'agent_reducer.dart';
import 'agent_repository.dart';
import 'agent_socket_client.dart';

String resolveAgentModel({
  required List<String> models,
  required String currentModel,
  String defaultModel = '',
}) {
  if (models.contains(currentModel)) return currentModel;
  if (models.contains(defaultModel)) return defaultModel;
  return models.firstOrNull ?? '';
}

String resolveAgentMode(String candidate) => normalizeAgentMode(candidate);

class AgentState {
  const AgentState({
    this.conversation = AgentConversationState.empty,
    this.connection = AgentConnectionStatus.disconnected,
    this.connectionError,
    this.models = const [],
    this.presets = const [
      AgentPreset(
        key: 'assist',
        label: 'Assist',
        desc: 'Allow recognized read-only operations; confirm all others',
      ),
      AgentPreset(
        key: 'authorized',
        label: 'Authorized',
        desc:
            'Allow read-only and recognized editing operations; confirm all others',
      ),
      AgentPreset(
        key: 'full_access',
        label: 'Full',
        desc:
            'Block only built-in high-risk commands; allow all other commands',
      ),
    ],
    this.tools = const [],
    this.plusAvailable = false,
    this.modelId = '',
    this.mode = 'assist',
    this.sessions = const [],
    this.sessionsLoading = false,
  });

  final AgentConversationState conversation;
  final AgentConnectionStatus connection;
  final String? connectionError;
  final List<String> models;
  final List<AgentPreset> presets;
  final List<Map<String, dynamic>> tools;
  final bool plusAvailable;
  final String modelId;
  final String mode;
  final List<AgentSessionSummary> sessions;
  final bool sessionsLoading;

  bool get connected => connection == AgentConnectionStatus.connected;
  bool get canSend => connected && !conversation.running;
  bool canSendDraft(String draft) => canSend && draft.trim().isNotEmpty;

  AgentState copyWith({
    AgentConversationState? conversation,
    AgentConnectionStatus? connection,
    String? connectionError,
    bool clearConnectionError = false,
    List<String>? models,
    List<AgentPreset>? presets,
    List<Map<String, dynamic>>? tools,
    bool? plusAvailable,
    String? modelId,
    String? mode,
    List<AgentSessionSummary>? sessions,
    bool? sessionsLoading,
  }) => AgentState(
    conversation: conversation ?? this.conversation,
    connection: connection ?? this.connection,
    connectionError: clearConnectionError
        ? null
        : connectionError ?? this.connectionError,
    models: models ?? this.models,
    presets: presets ?? this.presets,
    tools: tools ?? this.tools,
    plusAvailable: plusAvailable ?? this.plusAvailable,
    modelId: modelId ?? this.modelId,
    mode: mode ?? this.mode,
    sessions: sessions ?? this.sessions,
    sessionsLoading: sessionsLoading ?? this.sessionsLoading,
  );
}

class AgentController {
  AgentController({
    required AgentRepository repository,
    required AgentSocketClient socket,
    required AppStorage storage,
    required void Function(AgentState) emit,
    required AgentState Function() read,
    this.terminalBinding,
    Future<void> Function(Set<String>)? onPanelDataChanged,
  }) : _repository = repository,
       _socket = socket,
       _storage = storage,
       _emit = emit,
       _read = read {
    _panelRefresh = PanelCatalogRefresh(
      refresh: onPanelDataChanged ?? (_) async {},
      onError: () => _emit(
        _read().copyWith(
          conversation: _read().conversation.copyWith(
            notice: 'panel_refresh_failed',
          ),
        ),
      ),
    );
    _subscriptions.add(_socket.events.listen(_handleEvent));
    _subscriptions.add(_socket.connections.listen(_handleConnection));
    _subscriptions.add(_socket.errors.listen(_handleConnectionError));
  }

  final TerminalAgentBinding? terminalBinding;
  final _cancelledTerminalRequests = <String>{};
  final _activeTerminalRequests = <String>{};
  bool _disposed = false;
  late final PanelCatalogRefresh _panelRefresh;
  final AgentRepository _repository;
  final AgentSocketClient _socket;
  final AppStorage _storage;
  final void Function(AgentState) _emit;
  final AgentState Function() _read;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Future<void> open() async {
    try {
      await Future.wait([_socket.connect(), refreshSessions()]);
    } catch (error) {
      _handleConnectionError(error.toString());
    }
  }

  Future<void> refreshConnection() async {
    if (_read().conversation.running) return;
    _emit(_read().copyWith(clearConnectionError: true));
    _socket.disconnect();
    await _socket.connect();
  }

  void _handleConnection(AgentConnectionStatus status) {
    var next = _read().copyWith(
      connection: status,
      clearConnectionError: status != AgentConnectionStatus.disconnected,
    );
    if (status == AgentConnectionStatus.disconnected &&
        next.conversation.notice?.startsWith('policy_clamped:') == true) {
      next = next.copyWith(
        conversation: next.conversation.copyWith(clearNotice: true),
      );
    }
    if (status == AgentConnectionStatus.disconnected &&
        next.conversation.running) {
      next = next.copyWith(
        conversation: applyAgentEvent(next.conversation, const {
          'type': 'error',
          'message': 'agent_disconnected',
        }).copyWith(pendingApprovals: const []),
      );
    }
    _emit(next);
  }

  void _handleConnectionError(String error) {
    _emit(_read().copyWith(connectionError: error));
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['type'] == 'terminal_command_request' &&
        terminalBinding != null) {
      unawaited(_executeTerminalCommand(event));
      return;
    }
    if (event['type'] == 'terminal_command_cancel' && terminalBinding != null) {
      unawaited(_cancelTerminalCommand(event['requestId']?.toString() ?? ''));
      return;
    }
    if (event['type'] == 'panel_data_changed') {
      _panelRefresh.schedule(event['domains']);
      return;
    }
    final current = _read();
    if (event['type'] == 'ready') {
      final models = (event['models'] is List)
          ? (event['models'] as List)
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      final model = resolveAgentModel(
        models: models,
        currentModel: current.modelId,
        defaultModel: event['defaultModel']?.toString() ?? '',
      );
      final presets = mapList(event['presets'])
          .where((preset) => agentModes.contains(preset['key']))
          .map(AgentPreset.fromJson)
          .toList();
      _emit(
        current.copyWith(
          models: models,
          modelId: model,
          mode: resolveAgentMode(current.mode),
          presets: presets.isEmpty ? current.presets : presets,
          tools: mapList(event['tools']),
          plusAvailable: event['plusAvailable'] == true,
        ),
      );
      return;
    }
    final conversation = applyAgentEvent(current.conversation, event);
    _emit(current.copyWith(conversation: conversation));
    if (event['type'] == 'session_saved') unawaited(refreshSessions());
  }

  Future<void> refreshSessions({bool reportErrors = false}) async {
    if (_read().sessionsLoading) return;
    _emit(_read().copyWith(sessionsLoading: true));
    try {
      final sessions = terminalBinding == null
          ? await _repository.getSessions()
          : await _repository.getTerminalSessions(terminalBinding!.hostId);
      _emit(_read().copyWith(sessions: sessions, sessionsLoading: false));
    } catch (error) {
      _emit(_read().copyWith(sessionsLoading: false));
      if (reportErrors) rethrow;
    }
  }

  String? send(String input) {
    final content = input.trim();
    final current = _read();
    if (content.isEmpty) return null;
    if (!current.connected) return 'agent_not_connected';
    if (current.modelId.isEmpty) return 'agent_model_required';
    if (current.conversation.running) return 'agent_running';
    if (terminalBinding != null && !terminalBinding!.isConnected()) {
      return 'desktop.terminal.notConnected';
    }
    _emit(
      current.copyWith(
        conversation: current.conversation.copyWith(
          messages: [
            ...current.conversation.messages,
            createUserAgentMessage(content),
          ],
          running: true,
          aborted: false,
          clearError: true,
          clearNotice:
              current.conversation.notice?.startsWith('policy_clamped:') ==
              true,
        ),
      ),
    );
    if (terminalBinding != null) {
      _socket.runTerminal(
        input: content,
        modelId: current.modelId,
        permission: current.mode,
        sessionId: current.conversation.sessionId,
        hostId: terminalBinding!.hostId,
        hostName: terminalBinding!.hostName,
      );
      return null;
    }
    _socket.run(
      sessionId: current.conversation.sessionId,
      input: content,
      modelId: current.modelId,
      permission: current.mode,
    );
    return null;
  }

  void stop() {
    _socket.stop();
    for (final requestId in [..._activeTerminalRequests]) {
      unawaited(_cancelTerminalCommand(requestId));
    }
  }

  Future<void> _executeTerminalCommand(Map<String, dynamic> event) async {
    final binding = terminalBinding!;
    final id = event['requestId']?.toString() ?? '';
    _activeTerminalRequests.add(id);
    Map<String, dynamic> result;
    try {
      result = event['hostId'] != binding.hostId
          ? {'ok': false, 'error': '终端命令目标不匹配'}
          : await binding.execute(event['command']?.toString() ?? '', id, (
              progress,
            ) {
              if (!_disposed && !_cancelledTerminalRequests.contains(id)) {
                _socket.terminalProgress(id, progress);
              }
            });
    } catch (error) {
      result = {'ok': false, 'error': error.toString()};
    }
    _activeTerminalRequests.remove(id);
    if (!_disposed && !_cancelledTerminalRequests.remove(id)) {
      _socket.terminalResult(id, result);
    }
  }

  Future<void> _cancelTerminalCommand(String id) async {
    if (_cancelledTerminalRequests.contains(id)) return;
    _cancelledTerminalRequests.add(id);
    final result = await terminalBinding!.cancel(id);
    if (!_disposed && result['ok'] != true) {
      _emit(
        _read().copyWith(
          conversation: _read().conversation.copyWith(
            error: result['error']?.toString(),
          ),
        ),
      );
    }
  }

  void approve(String requestId, bool approved, {String scope = 'once'}) {
    _socket.approve(requestId, approved: approved, scope: scope);
    _emit(
      _read().copyWith(
        conversation: applyAgentApprovalResponse(
          _read().conversation,
          requestId,
          approved,
        ),
      ),
    );
  }

  Future<void> setModel(String model) async {
    if (terminalBinding == null) {
      await _storage.setAgentModel(model);
    } else {
      await _storage.setTerminalAgentModel(model);
    }
    _emit(_read().copyWith(modelId: model));
  }

  Future<void> setMode(String mode) async {
    mode = normalizeAgentMode(mode);
    if (terminalBinding == null) {
      await _storage.setAgentMode(mode);
    } else {
      await _storage.setTerminalAgentMode(mode);
    }
    _emit(_read().copyWith(mode: mode));
  }

  void newConversation() {
    if (_read().conversation.running) return;
    _emit(_read().copyWith(conversation: AgentConversationState.empty));
  }

  Future<void> loadSession(String id) async {
    if (_read().conversation.running) return;
    final session = await _repository.getSession(id);
    if (session.scope != (terminalBinding == null ? 'ops' : 'terminal') ||
        terminalBinding != null &&
            session.hostId != terminalBinding!.hostId &&
            !session.hostIds.contains(terminalBinding!.hostId)) {
      throw StateError('Assistant session scope does not match');
    }
    final current = _read();
    _emit(
      current.copyWith(
        conversation: conversationFromSession(session),
        modelId: resolveAgentModel(
          models: current.models,
          currentModel: current.models.contains(session.modelId)
              ? session.modelId
              : current.modelId,
        ),
        mode: resolveAgentMode(session.permission),
      ),
    );
  }

  Future<void> renameSession(String id, String title) async {
    if (title.trim().isEmpty) return;
    await _repository.renameSession(id, title);
    await refreshSessions();
    if (_read().conversation.sessionId == id) {
      _emit(
        _read().copyWith(
          conversation: _read().conversation.copyWith(title: title.trim()),
        ),
      );
    }
  }

  Future<void> deleteSession(String id) async {
    await _repository.deleteSession(id);
    if (_read().conversation.sessionId == id) newConversation();
    await refreshSessions();
  }

  Future<void> clearSessions() async {
    if (terminalBinding == null) {
      await _repository.clearSessions();
    } else {
      await _repository.clearTerminalSessions(terminalBinding!.hostId);
    }
    newConversation();
    await refreshSessions();
  }

  Future<String?> editAndResend(AgentMessage message, String content) async {
    final state = _read();
    final turnIndex = userTurnIndex(state.conversation.messages, message.id);
    if (turnIndex < 0 || state.conversation.sessionId.isEmpty) {
      return 'agent_message_not_saved';
    }
    final session = await _repository.editMessage(
      state.conversation.sessionId,
      turnIndex: turnIndex,
      content: content,
    );
    _emit(_read().copyWith(conversation: conversationFromSession(session)));
    return send(content);
  }

  Future<String?> regenerate(AgentMessage assistant) async {
    final user = previousUserMessage(
      _read().conversation.messages,
      assistant.id,
    );
    if (user == null) return 'agent_previous_message_missing';
    return editAndResend(user, user.text);
  }

  Future<void> fork(AgentMessage assistant) async {
    final state = _read();
    final user = previousUserMessage(state.conversation.messages, assistant.id);
    if (user == null || state.conversation.sessionId.isEmpty) return;
    final turnIndex = userTurnIndex(state.conversation.messages, user.id);
    final session = await _repository.forkSession(
      state.conversation.sessionId,
      turnIndex: turnIndex,
      messageIndex: assistant.sourceIndex,
    );
    _emit(_read().copyWith(conversation: conversationFromSession(session)));
    await refreshSessions();
  }

  void dismissNotices() {
    _emit(
      _read().copyWith(
        conversation: _read().conversation.copyWith(
          clearNotice: true,
          clearPlusRequired: true,
        ),
      ),
    );
  }

  void dismissConnectionError() {
    _emit(_read().copyWith(clearConnectionError: true));
  }

  void dispose() {
    _disposed = true;
    for (final id in _activeTerminalRequests) {
      unawaited(terminalBinding!.cancel(id));
    }
    _panelRefresh.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _socket.dispose();
  }
}
