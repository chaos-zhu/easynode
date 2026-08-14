import 'dart:async';

import '../../core/storage/app_storage.dart';
import 'agent_models.dart';
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

String resolveAgentMode(String candidate, {String fallback = 'review'}) {
  const modes = {'review', 'assist', 'authorized'};
  if (modes.contains(candidate)) return candidate;
  return modes.contains(fallback) ? fallback : 'review';
}

class AgentState {
  const AgentState({
    this.conversation = AgentConversationState.empty,
    this.connection = AgentConnectionStatus.disconnected,
    this.connectionError,
    this.models = const [],
    this.presets = const [
      AgentPreset(
        key: 'review',
        label: 'Review',
        desc: 'Confirm all host operations',
      ),
      AgentPreset(
        key: 'assist',
        label: 'Assist',
        desc: 'Automatically run explicit read-only operations',
      ),
      AgentPreset(
        key: 'authorized',
        label: 'Authorized',
        desc: 'Automatically run ordinary operations',
      ),
    ],
    this.tools = const [],
    this.plusAvailable = false,
    this.modelId = '',
    this.mode = 'review',
    this.hostIds = const [],
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
  final List<String> hostIds;
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
    List<String>? hostIds,
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
    hostIds: hostIds ?? this.hostIds,
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
  }) : _repository = repository,
       _socket = socket,
       _storage = storage,
       _emit = emit,
       _read = read {
    _subscriptions.add(_socket.events.listen(_handleEvent));
    _subscriptions.add(_socket.connections.listen(_handleConnection));
    _subscriptions.add(_socket.errors.listen(_handleConnectionError));
  }

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
      final presets = mapList(
        event['presets'],
      ).map(AgentPreset.fromJson).toList();
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
      final sessions = await _repository.getSessions();
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
        ),
      ),
    );
    _socket.run(
      sessionId: current.conversation.sessionId,
      input: content,
      modelId: current.modelId,
      permission: current.mode,
      hostIds: current.hostIds,
    );
    return null;
  }

  void stop() => _socket.stop();

  void approve(String requestId, bool approved, {String scope = 'once'}) {
    _socket.approve(requestId, approved: approved, scope: scope);
    _emit(
      _read().copyWith(
        conversation: removeAgentApproval(_read().conversation, requestId),
      ),
    );
  }

  Future<void> setModel(String model) async {
    await _storage.setAgentModel(model);
    _emit(_read().copyWith(modelId: model));
  }

  Future<void> setMode(String mode) async {
    if (!const {'review', 'assist', 'authorized'}.contains(mode)) return;
    await _storage.setAgentMode(mode);
    _emit(_read().copyWith(mode: mode));
  }

  void setHosts(List<String> hostIds) {
    _emit(_read().copyWith(hostIds: List.unmodifiable(hostIds)));
  }

  void newConversation() {
    if (_read().conversation.running) return;
    _emit(_read().copyWith(conversation: AgentConversationState.empty));
  }

  Future<void> loadSession(String id) async {
    if (_read().conversation.running) return;
    final session = await _repository.getSession(id);
    if (session.scope != 'ops') throw StateError('Not an ops session');
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
        mode: resolveAgentMode(session.permission, fallback: current.mode),
        hostIds: session.hostIds,
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
    await _repository.clearSessions();
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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _socket.dispose();
  }
}
