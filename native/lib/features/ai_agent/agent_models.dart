import 'dart:collection';

Map<String, dynamic> stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, dynamic>> mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(stringMap).toList(growable: false);
}

int intValue(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

class AgentProviderConfig {
  AgentProviderConfig({
    this.providerType = 'openai-compatible',
    this.apiUrl = '',
    this.apiKey = '',
    this.models = const [],
    this.contextLimit = 65536,
    this.maxSteps = 25,
    this.nativeAgentEnabled = true,
    Map<String, dynamic> raw = const {},
  }) : raw = UnmodifiableMapView(Map<String, dynamic>.from(raw));

  final String providerType;
  final String apiUrl;
  final String apiKey;
  final List<String> models;
  final int contextLimit;
  final int maxSteps;
  final bool nativeAgentEnabled;
  final Map<String, dynamic> raw;

  factory AgentProviderConfig.fromJson(Map<String, dynamic> json) {
    final ui = stringMap(json['ui']);
    final provider = json['providerType']?.toString() ?? '';
    return AgentProviderConfig(
      providerType:
          const {'openai-compatible', 'anthropic', 'google'}.contains(provider)
          ? provider
          : 'openai-compatible',
      apiUrl: json['apiUrl']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      models: (json['models'] is List)
          ? (json['models'] as List)
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      contextLimit: intValue(json['contextLimit'], 65536).clamp(1024, 1 << 30),
      maxSteps: intValue(json['maxSteps'], 25).clamp(1, 50),
      nativeAgentEnabled: ui['nativeAgentEnabled'] != false,
      raw: json,
    );
  }

  AgentProviderConfig copyWith({
    String? providerType,
    String? apiUrl,
    String? apiKey,
    List<String>? models,
    int? contextLimit,
    int? maxSteps,
    bool? nativeAgentEnabled,
  }) {
    return AgentProviderConfig(
      providerType: providerType ?? this.providerType,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      contextLimit: contextLimit ?? this.contextLimit,
      maxSteps: maxSteps ?? this.maxSteps,
      nativeAgentEnabled: nativeAgentEnabled ?? this.nativeAgentEnabled,
      raw: raw,
    );
  }

  Map<String, dynamic> toProviderJson() {
    final json = Map<String, dynamic>.from(raw);
    json
      ..['providerType'] = providerType
      ..['apiUrl'] = apiUrl.trim()
      ..['apiKey'] = apiKey.trim()
      ..['models'] = models
      ..['contextLimit'] = contextLimit
      ..['maxSteps'] = maxSteps;
    json['ui'] = {
      ...stringMap(raw['ui']),
      'nativeAgentEnabled': nativeAgentEnabled,
    };
    json.remove('_id');
    return json;
  }
}

class AgentHostPolicy {
  const AgentHostPolicy({
    required this.hostId,
    required this.name,
    required this.address,
    this.enabled = true,
    this.maxEffect = 'write',
    this.maxMode = 'authorized',
  });

  final String hostId;
  final String name;
  final String address;
  final bool enabled;
  final String maxEffect;
  final String maxMode;

  AgentHostPolicy copyWith({
    bool? enabled,
    String? maxEffect,
    String? maxMode,
  }) {
    return AgentHostPolicy(
      hostId: hostId,
      name: name,
      address: address,
      enabled: enabled ?? this.enabled,
      maxEffect: maxEffect ?? this.maxEffect,
      maxMode: maxMode ?? this.maxMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'maxEffect': maxEffect,
    'maxMode': maxMode,
  };
}

class AgentUsage {
  const AgentUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.cachedInputTokens = 0,
    this.reasoningTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int cachedInputTokens;
  final int reasoningTokens;

  factory AgentUsage.fromJson(Object? value) {
    final json = stringMap(value);
    return AgentUsage(
      inputTokens: intValue(json['inputTokens']),
      outputTokens: intValue(json['outputTokens']),
      totalTokens: intValue(json['totalTokens']),
      cachedInputTokens: intValue(json['cachedInputTokens']),
      reasoningTokens: intValue(json['reasoningTokens']),
    );
  }

  AgentUsage add(AgentUsage other) => AgentUsage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    totalTokens: totalTokens + other.totalTokens,
    cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
    reasoningTokens: reasoningTokens + other.reasoningTokens,
  );
}

class AgentSessionSummary {
  const AgentSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final int updatedAt;
  final int messageCount;

  factory AgentSessionSummary.fromJson(Map<String, dynamic> json) =>
      AgentSessionSummary(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        title: json['title']?.toString() ?? '',
        updatedAt: intValue(json['updatedAt']),
        messageCount: intValue(json['messageCount']),
      );
}

class AgentSession {
  AgentSession({
    required this.id,
    required this.title,
    required this.scope,
    required this.modelId,
    required this.permission,
    required this.hostIds,
    required this.messages,
    required this.toolMeta,
    required this.turnMeta,
    required this.usage,
  });

  final String id;
  final String title;
  final String scope;
  final String modelId;
  final String permission;
  final List<String> hostIds;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic> toolMeta;
  final List<Map<String, dynamic>> turnMeta;
  final AgentUsage usage;

  factory AgentSession.fromJson(Map<String, dynamic> json) => AgentSession(
    id: (json['id'] ?? json['_id'] ?? '').toString(),
    title: json['title']?.toString() ?? '',
    scope: json['scope']?.toString() ?? 'ops',
    modelId: json['modelId']?.toString() ?? '',
    permission: json['permission']?.toString() ?? 'review',
    hostIds: json['hostIds'] is List
        ? (json['hostIds'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
        : const [],
    messages: mapList(json['messages']),
    toolMeta: stringMap(json['toolMeta']),
    turnMeta: mapList(json['turnMeta']),
    usage: AgentUsage.fromJson(json['usage']),
  );
}

enum AgentMessageRole { user, assistant }

sealed class AgentMessagePart {
  const AgentMessagePart();
}

class AgentTextPart extends AgentMessagePart {
  const AgentTextPart(this.text);
  final String text;
}

class AgentReasoningPart extends AgentMessagePart {
  const AgentReasoningPart(this.text, {this.done = false});
  final String text;
  final bool done;
}

enum AgentToolStatus { running, awaitingApproval, done, error, denied }

class AgentToolPart extends AgentMessagePart {
  const AgentToolPart({
    required this.toolCallId,
    required this.tool,
    required this.input,
    this.status = AgentToolStatus.running,
    this.output,
    this.error,
    this.durationMs,
    this.risk,
    this.approval,
  });

  final String toolCallId;
  final String tool;
  final Map<String, dynamic> input;
  final AgentToolStatus status;
  final Object? output;
  final String? error;
  final int? durationMs;
  final Map<String, dynamic>? risk;
  final Map<String, dynamic>? approval;

  AgentToolPart copyWith({
    AgentToolStatus? status,
    Object? output,
    bool clearOutput = false,
    String? error,
    bool clearError = false,
    int? durationMs,
    Map<String, dynamic>? risk,
    Map<String, dynamic>? approval,
  }) => AgentToolPart(
    toolCallId: toolCallId,
    tool: tool,
    input: input,
    status: status ?? this.status,
    output: clearOutput ? null : output ?? this.output,
    error: clearError ? null : error ?? this.error,
    durationMs: durationMs ?? this.durationMs,
    risk: risk ?? this.risk,
    approval: approval ?? this.approval,
  );
}

class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.parts,
    required this.createdAt,
    this.sourceIndex,
    this.usage,
  });

  final String id;
  final AgentMessageRole role;
  final List<AgentMessagePart> parts;
  final int createdAt;
  final int? sourceIndex;
  final AgentUsage? usage;

  AgentMessage copyWith({List<AgentMessagePart>? parts, AgentUsage? usage}) =>
      AgentMessage(
        id: id,
        role: role,
        parts: parts ?? this.parts,
        createdAt: createdAt,
        sourceIndex: sourceIndex,
        usage: usage ?? this.usage,
      );

  String get text => parts
      .whereType<AgentTextPart>()
      .map((part) => part.text)
      .join('\n\n')
      .trim();
}

class AgentApproval {
  const AgentApproval({
    required this.requestId,
    required this.toolCallId,
    required this.tool,
    required this.input,
    required this.createdAt,
    this.preview,
    this.hostName,
    this.effect,
    this.targets = const [],
    this.sensitiveDisclosure = false,
    this.risk,
    this.grantLabel,
    this.grantable = true,
  });

  final String requestId;
  final String toolCallId;
  final String tool;
  final Map<String, dynamic> input;
  final int createdAt;
  final Map<String, dynamic>? preview;
  final String? hostName;
  final String? effect;
  final List<String> targets;
  final bool sensitiveDisclosure;
  final Map<String, dynamic>? risk;
  final String? grantLabel;
  final bool grantable;

  factory AgentApproval.fromEvent(Map<String, dynamic> event) => AgentApproval(
    requestId: event['requestId']?.toString() ?? '',
    toolCallId: event['toolCallId']?.toString() ?? '',
    tool: event['tool']?.toString() ?? '',
    input: stringMap(event['input']),
    preview: event['preview'] is Map ? stringMap(event['preview']) : null,
    hostName: event['hostName']?.toString(),
    effect: event['effect']?.toString(),
    targets: event['targets'] is List
        ? (event['targets'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
        : const [],
    sensitiveDisclosure: event['sensitiveDisclosure'] == true,
    risk: event['risk'] is Map ? stringMap(event['risk']) : null,
    grantLabel: event['grantLabel']?.toString(),
    grantable: event['grantable'] != false,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

class AgentPreset {
  const AgentPreset({
    required this.key,
    required this.label,
    required this.desc,
  });
  final String key;
  final String label;
  final String desc;

  factory AgentPreset.fromJson(Map<String, dynamic> json) => AgentPreset(
    key: json['key']?.toString() ?? 'review',
    label: json['label']?.toString() ?? '',
    desc: json['desc']?.toString() ?? '',
  );
}
