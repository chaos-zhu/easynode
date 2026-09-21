class ScheduledTaskScript {
  const ScheduledTaskScript({
    required this.type,
    this.command = '',
    this.useBase64 = false,
    this.scriptId = '',
  });

  final String type;
  final String command;
  final bool useBase64;
  final String scriptId;

  bool get isLibrary => type == 'library';

  factory ScheduledTaskScript.fromJson(Object? value) {
    final json = _map(value);
    return ScheduledTaskScript(
      type: json['type']?.toString() == 'library' ? 'library' : 'inline',
      command: json['command']?.toString() ?? '',
      useBase64: json['useBase64'] == true,
      scriptId: json['scriptId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => isLibrary
      ? {'type': 'library', 'scriptId': scriptId}
      : {'type': 'inline', 'command': command, 'useBase64': useBase64};
}

class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.name,
    required this.enabled,
    required this.hostIds,
    required this.cron,
    required this.timezone,
    required this.timeoutSeconds,
    required this.script,
    required this.notificationPolicy,
    this.nextRunAt,
    this.nextRunTimes = const [],
    this.lastRunAt,
    this.lastRunStatus = '',
    this.disabledReason = '',
  });

  final String id;
  final String name;
  final bool enabled;
  final List<String> hostIds;
  final String cron;
  final String timezone;
  final int timeoutSeconds;
  final ScheduledTaskScript script;
  final String notificationPolicy;
  final DateTime? nextRunAt;
  final List<DateTime> nextRunTimes;
  final DateTime? lastRunAt;
  final String lastRunStatus;
  final String disabledReason;

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
    id: (json['id'] ?? json['_id'] ?? '').toString(),
    name: json['name']?.toString() ?? '',
    enabled: json['enabled'] != false,
    hostIds: _strings(json['hostIds']),
    cron: json['cron']?.toString() ?? '',
    timezone: json['timezone']?.toString() ?? 'Asia/Shanghai',
    timeoutSeconds: _integer(json['timeoutSeconds'], 120),
    script: ScheduledTaskScript.fromJson(json['script']),
    notificationPolicy: json['notificationPolicy']?.toString() ?? 'failure',
    nextRunAt: _date(json['nextRunAt']),
    nextRunTimes: _dates(json['nextRunTimes']),
    lastRunAt: _date(json['lastRunAt']),
    lastRunStatus: json['lastRunStatus']?.toString() ?? '',
    disabledReason: json['disabledReason']?.toString() ?? '',
  );
}

class ScheduledTaskFormData {
  ScheduledTaskFormData({
    this.id,
    required this.name,
    required this.enabled,
    required this.hostIds,
    required this.cron,
    required this.timezone,
    required this.timeoutSeconds,
    required this.script,
    required this.notificationPolicy,
  });

  String? id;
  String name;
  bool enabled;
  List<String> hostIds;
  String cron;
  String timezone;
  int timeoutSeconds;
  ScheduledTaskScript script;
  String notificationPolicy;

  bool get isEdit => id?.isNotEmpty == true;

  factory ScheduledTaskFormData.create() => ScheduledTaskFormData(
    name: '',
    enabled: true,
    hostIds: [],
    cron: '0 0 * * *',
    timezone: 'Asia/Shanghai',
    timeoutSeconds: 120,
    script: const ScheduledTaskScript(type: 'inline'),
    notificationPolicy: 'failure',
  );

  factory ScheduledTaskFormData.fromTask(ScheduledTask task) =>
      ScheduledTaskFormData(
        id: task.id,
        name: task.name,
        enabled: task.enabled,
        hostIds: [...task.hostIds],
        cron: task.cron,
        timezone: task.timezone,
        timeoutSeconds: task.timeoutSeconds,
        script: task.script,
        notificationPolicy: task.notificationPolicy,
      );

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'enabled': enabled,
    'hostIds': hostIds,
    'cron': cron.trim(),
    'timezone': timezone,
    'timeoutSeconds': timeoutSeconds,
    'script': script.toJson(),
    'notificationPolicy': notificationPolicy,
  };
}

class ScheduledTaskRun {
  const ScheduledTaskRun({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.trigger,
    required this.status,
    required this.targetCount,
    this.startedAt,
    this.endedAt,
    this.durationMs = 0,
    this.reason = '',
    this.error = '',
    this.targets = const [],
  });

  final String id;
  final String taskId;
  final String taskName;
  final String trigger;
  final String status;
  final int targetCount;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int durationMs;
  final String reason;
  final String error;
  final List<ScheduledTaskTargetRun> targets;

  bool get isRunning => status == 'running';
  bool get isComplete => const {
    'success',
    'partial',
    'failed',
    'timeout',
    'cancelled',
    'skipped',
    'interrupted',
  }.contains(status);

  factory ScheduledTaskRun.fromJson(Map<String, dynamic> json) =>
      ScheduledTaskRun(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        taskId: json['taskId']?.toString() ?? '',
        taskName: json['taskName']?.toString() ?? '',
        trigger: json['trigger']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        targetCount: _integer(json['targetCount'], 0),
        startedAt: _date(json['startedAt']),
        endedAt: _date(json['endedAt']),
        durationMs: _integer(json['durationMs'], 0),
        reason: json['reason']?.toString() ?? '',
        error: json['error']?.toString() ?? '',
        targets: (json['targets'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => ScheduledTaskTargetRun.fromJson(_map(item)))
            .toList(growable: false),
      );
}

class ScheduledTaskTargetRun {
  const ScheduledTaskTargetRun({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.status,
    this.stdout = '',
    this.stderr = '',
    this.error = '',
    this.durationMs = 0,
    this.exitCode,
    this.truncated = false,
    this.timeoutPhase = '',
  });

  final String id;
  final String hostId;
  final String hostName;
  final String status;
  final String stdout;
  final String stderr;
  final String error;
  final int durationMs;
  final int? exitCode;
  final bool truncated;
  final String timeoutPhase;

  factory ScheduledTaskTargetRun.fromJson(Map<String, dynamic> json) =>
      ScheduledTaskTargetRun(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        hostId: json['hostId']?.toString() ?? '',
        hostName: json['hostName']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        stdout: json['stdout']?.toString() ?? '',
        stderr: json['stderr']?.toString() ?? '',
        error: json['error']?.toString() ?? '',
        durationMs: _integer(json['durationMs'], 0),
        exitCode: json['exitCode'] is num
            ? (json['exitCode'] as num).toInt()
            : int.tryParse(json['exitCode']?.toString() ?? ''),
        truncated: json['truncated'] == true,
        timeoutPhase: json['timeoutPhase']?.toString() ?? '',
      );
}

class ScheduledTaskRunPage {
  const ScheduledTaskRunPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ScheduledTaskRun> items;
  final int total;
  final int page;
  final int pageSize;

  factory ScheduledTaskRunPage.fromJson(Map<String, dynamic> json) =>
      ScheduledTaskRunPage(
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => ScheduledTaskRun.fromJson(_map(item)))
            .toList(growable: false),
        total: _integer(json['total'], 0),
        page: _integer(json['page'], 1),
        pageSize: _integer(json['pageSize'], 20),
      );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<String> _strings(Object? value) => (value as List? ?? const [])
    .map((item) => item.toString())
    .toList(growable: false);

int _integer(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  final milliseconds = value is num
      ? value.toInt()
      : int.tryParse(value.toString());
  if (milliseconds != null) {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  return DateTime.tryParse(value.toString());
}

List<DateTime> _dates(Object? value) => (value as List? ?? const [])
    .map(_date)
    .whereType<DateTime>()
    .toList(growable: false);
