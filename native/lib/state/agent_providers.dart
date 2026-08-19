import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_storage.dart';
import '../features/ai_agent/agent_controller.dart';
import '../features/ai_agent/agent_models.dart';
import '../features/ai_agent/agent_repository.dart';
import '../features/ai_agent/agent_socket_client.dart';
import '../features/servers/server_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';
import 'host_list_notifier.dart';
import 'storage_providers.dart';

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(ref.watch(apiClientProvider));
});

class AgentSettingsData {
  const AgentSettingsData({required this.config, required this.hostPolicies});
  final AgentProviderConfig config;
  final List<AgentHostPolicy> hostPolicies;

  AgentSettingsData copyWith({
    AgentProviderConfig? config,
    List<AgentHostPolicy>? hostPolicies,
  }) => AgentSettingsData(
    config: config ?? this.config,
    hostPolicies: hostPolicies ?? this.hostPolicies,
  );
}

class AgentSettingsNotifier extends AsyncNotifier<AgentSettingsData> {
  AgentRepository get _repository => ref.read(agentRepositoryProvider);

  @override
  Future<AgentSettingsData> build() async {
    final results = await Future.wait<Object>([
      _repository.getConfig(),
      ref.watch(hostListProvider.future),
    ]);
    final config = results[0] as AgentProviderConfig;
    final hosts = results[1] as List<ServerModel>;
    await ref
        .read(appStorageProvider)
        .setNativeAgentEnabledCache(config.nativeAgentEnabled);
    return AgentSettingsData(
      config: config,
      hostPolicies: hosts.map(_agentPolicyFromHost).toList(growable: false),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> saveSettings({
    required AgentProviderConfig config,
    required List<AgentHostPolicy> hostPolicies,
    required List<AgentHostPolicy> changedHostPolicies,
  }) async {
    final current = state.valueOrNull;
    final previousEnabled = current?.config.nativeAgentEnabled;

    // Provider data and UI preferences use separate endpoints. Keeping the
    // existing preference out of the provider write prevents a stale settings
    // form from overwriting another client's UI preference.
    if (config.nativeAgentEnabled) {
      await _repository.saveProvider(
        config.copyWith(
          nativeAgentEnabled: previousEnabled ?? config.nativeAgentEnabled,
        ),
      );
    }
    var savedEnabled = config.nativeAgentEnabled;
    if (previousEnabled == null ||
        previousEnabled != config.nativeAgentEnabled) {
      savedEnabled = await _repository.setNativeAgentEnabled(
        config.nativeAgentEnabled,
      );
    }
    await Future.wait(changedHostPolicies.map(_repository.updateHostPolicy));

    final savedConfig = await _repository.getConfig();
    await ref.read(appStorageProvider).setNativeAgentEnabledCache(savedEnabled);
    state = AsyncData(
      AgentSettingsData(
        config: savedConfig.copyWith(nativeAgentEnabled: savedEnabled),
        hostPolicies: List.unmodifiable(hostPolicies),
      ),
    );
    if (changedHostPolicies.isNotEmpty) {
      await ref.read(hostListProvider.notifier).refresh(throwOnError: true);
    }
  }

  Future<List<String>> discoverModels({
    required String apiUrl,
    required String apiKey,
  }) => _repository.discoverModels(apiUrl: apiUrl, apiKey: apiKey);
}

final agentSettingsProvider =
    AsyncNotifierProvider<AgentSettingsNotifier, AgentSettingsData>(
      AgentSettingsNotifier.new,
    );

final agentHostPoliciesProvider = Provider<List<AgentHostPolicy>>((ref) {
  final hosts = ref.watch(hostListProvider).valueOrNull;
  if (hosts == null) {
    return ref.watch(agentSettingsProvider).valueOrNull?.hostPolicies ??
        const <AgentHostPolicy>[];
  }
  return hosts.map(_agentPolicyFromHost).toList(growable: false);
});

AgentHostPolicy _agentPolicyFromHost(ServerModel host) => AgentHostPolicy(
  hostId: host.id,
  name: host.displayName,
  address: '${host.host}:${host.port}',
  enabled: host.aiPolicy.enabled,
  maxEffect: host.aiPolicy.maxEffect,
  maxMode: host.aiPolicy.maxMode,
);

final nativeAgentEnabledProvider = Provider<bool>((ref) {
  final remote = ref.watch(agentSettingsProvider).valueOrNull?.config;
  return remote?.nativeAgentEnabled ??
      ref.watch(appStorageProvider).nativeAgentEnabledCache ??
      true;
});

class AgentStateNotifier extends StateNotifier<AgentState> {
  AgentStateNotifier({
    required AgentRepository repository,
    required AgentSocketClient socket,
    required AppStorage storage,
  }) : super(AgentState(modelId: storage.agentModel, mode: storage.agentMode)) {
    _controller = AgentController(
      repository: repository,
      socket: socket,
      storage: storage,
      emit: (next) {
        if (mounted) state = next;
      },
      read: () => state,
    );
  }

  late final AgentController _controller;

  Future<void> open() => _controller.open();
  Future<void> refreshConnection() => _controller.refreshConnection();
  Future<void> refreshSessions({bool reportErrors = false}) =>
      _controller.refreshSessions(reportErrors: reportErrors);
  String? send(String input) => _controller.send(input);
  void stop() => _controller.stop();
  void approve(String id, bool approved, {String scope = 'once'}) =>
      _controller.approve(id, approved, scope: scope);
  Future<void> setModel(String model) => _controller.setModel(model);
  Future<void> setMode(String mode) => _controller.setMode(mode);
  void setHosts(List<String> hostIds) => _controller.setHosts(hostIds);
  void newConversation() => _controller.newConversation();
  Future<void> loadSession(String id) => _controller.loadSession(id);
  Future<void> renameSession(String id, String title) =>
      _controller.renameSession(id, title);
  Future<void> deleteSession(String id) => _controller.deleteSession(id);
  Future<void> clearSessions() => _controller.clearSessions();
  Future<String?> editAndResend(AgentMessage message, String content) =>
      _controller.editAndResend(message, content);
  Future<String?> regenerate(AgentMessage message) =>
      _controller.regenerate(message);
  Future<void> fork(AgentMessage message) => _controller.fork(message);
  void dismissNotices() => _controller.dismissNotices();
  void dismissConnectionError() => _controller.dismissConnectionError();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

final agentControllerProvider =
    StateNotifierProvider.autoDispose<AgentStateNotifier, AgentState>((ref) {
      final auth = ref.watch(authProvider);
      final session = auth.session;
      if (session == null) {
        throw StateError('agentControllerProvider read while signed out');
      }
      final socket = AgentSocketClient(
        authSession: session,
        cookieStore: ref.watch(cookieStoreProvider),
      );
      return AgentStateNotifier(
        repository: ref.watch(agentRepositoryProvider),
        socket: socket,
        storage: ref.watch(appStorageProvider),
      );
    });

/// Keeps the socket/controller alive for the lifetime of the authenticated
/// root overlay, independently from whether the conversation panel is open.
final agentKeepAliveProvider = Provider<bool>((ref) {
  ref.watch(agentControllerProvider);
  return true;
});
