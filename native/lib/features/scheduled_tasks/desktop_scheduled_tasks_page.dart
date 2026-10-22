import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_dropdown_menu.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_select.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_scheduled_task_revision_provider.dart';
import '../../state/desktop_script_catalog_provider.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../scripts/desktop_script_dialogs.dart';
import 'scheduled_task_models.dart';
import 'scheduled_task_ui.dart';

const _runStatuses = [
  'running',
  'success',
  'partial',
  'failed',
  'timeout',
  'cancelled',
  'skipped',
  'interrupted',
];

class DesktopScheduledTasksPage extends ConsumerStatefulWidget {
  const DesktopScheduledTasksPage({super.key});
  @override
  ConsumerState<DesktopScheduledTasksPage> createState() =>
      _DesktopScheduledTasksPageState();
}

class _DesktopScheduledTasksPageState
    extends ConsumerState<DesktopScheduledTasksPage> {
  final _search = TextEditingController();
  List<ScheduledTask> _tasks = [];
  ScheduledTaskRunPage? _runs;
  bool _history = false, _loading = true, _busy = false;
  String _taskFilter = '', _statusFilter = '';
  String? _error;
  int _page = 1, _size = 20;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(scheduledTaskRepositoryProvider);
      if (_history) {
        final runs = await repo.fetchRuns(
          taskId: _taskFilter,
          status: _statusFilter,
          page: _page,
          pageSize: _size,
        );
        if (mounted) setState(() => _runs = runs);
      } else {
        final tasks = await repo.fetchTasks(keyword: _search.text);
        if (mounted) setState(() => _tasks = tasks);
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ScheduledTask? task]) async {
    try {
      final detail = task == null
          ? null
          : await ref.read(scheduledTaskRepositoryProvider).fetchTask(task.id);
      if (!mounted) return;
      final saved = await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DesktopScheduledTaskDialog(task: detail),
      );
      if (saved == true && mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    }
  }

  Future<void> _run(ScheduledTask task) async {
    if (!await managementConfirm(
          context,
          mx(context, '立即执行任务「${task.name}」？', 'Run ${task.name} now?'),
        ) ||
        !mounted) {
      return;
    }
    await _action(() async {
      final run = await ref
          .read(scheduledTaskRepositoryProvider)
          .runTask(task.id);
      if (mounted) {
        unawaited(
          showManagementDrawer<void>(
            context,
            (_) => DesktopScheduledRunDetail(runId: run.id),
          ),
        );
      }
    });
  }

  void _openRun(ScheduledTaskRun run) => unawaited(
    showManagementDrawer<void>(
      context,
      (_) => DesktopScheduledRunDetail(runId: run.id),
    ),
  );

  Widget _taskToolbar() => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width * .36).clamp(
                280,
                460,
              ),
            ),
            child: TextField(
              key: const Key('scheduled-task-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _load(),
              style: const TextStyle(fontSize: 13),
              decoration:
                  desktopInputDecoration(
                    context,
                    controlHeight: 36,
                    hint: mx(
                      context,
                      '搜索任务名称、Cron 或时区',
                      'Search task name, Cron or timezone',
                    ),
                  ).copyWith(
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 36,
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: mx(context, '清除搜索', 'Clear search'),
                            icon: const Icon(Icons.cancel_outlined, size: 14),
                            onPressed: () {
                              _search.clear();
                              _load();
                            },
                          ),
                  ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      ManagementButton(
        label: mx(context, '刷新', 'Refresh'),
        icon: Icons.refresh,
        onPressed: _loading ? null : _load,
      ),
      const SizedBox(width: 8),
      ManagementButton(
        key: const Key('scheduled-task-add'),
        label: mx(context, '新建任务', 'New task'),
        primary: true,
        icon: Icons.add,
        onPressed: _busy ? null : () => _edit(),
      ),
    ],
  );

  Widget _historyToolbar() => LayoutBuilder(
    builder: (context, size) {
      final filters = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 190,
            child: DesktopSelect(
              key: const Key('scheduled-history-task'),
              controlHeight: 36,
              clearable: true,
              placeholder: mx(context, '全部任务', 'All tasks'),
              options: {
                '': mx(context, '全部任务', 'All tasks'),
                for (final t in _tasks) t.id: t.name,
              },
              values: [_taskFilter],
              onSelected: (v) {
                _taskFilter = v;
                _page = 1;
                _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 190,
            child: DesktopSelect(
              key: const Key('scheduled-history-status'),
              controlHeight: 36,
              clearable: true,
              placeholder: mx(context, '全部状态', 'All statuses'),
              options: {
                '': mx(context, '全部状态', 'All statuses'),
                for (final s in _runStatuses)
                  s: scheduledTaskStatusLabel(AppLocalizations.of(context), s),
              },
              values: [_statusFilter],
              onSelected: (v) {
                _statusFilter = v;
                _page = 1;
                _load();
              },
            ),
          ),
        ],
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ManagementButton(
            label: mx(context, '刷新', 'Refresh'),
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
          ManagementButton(
            label: mx(context, '清空记录', 'Clear records'),
            icon: Icons.delete_outline,
            danger: true,
            onPressed: _busy ? null : _clearHistory,
          ),
        ],
      );
      return size.maxWidth >= 650
          ? Row(children: [filters, const Spacer(), actions])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                filters,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
    },
  );

  Future<void> _clearHistory() async {
    if (!await managementConfirm(
          context,
          mx(
            context,
            '清空所有已完成的执行历史？运行中的记录会保留。',
            'Clear completed execution history? Running records will be kept.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _action(() async {
      await ref.read(scheduledTaskRepositoryProvider).clearRuns();
      _page = 1;
    });
  }

  Widget _status(String status) => ManagementTag(
    scheduledTaskStatusLabel(AppLocalizations.of(context), status),
    color: scheduledTaskStatusColor(context, status),
  );
  @override
  Widget build(BuildContext context) {
    ref.listen(
      desktopScheduledTaskRevisionProvider,
      (_, _) => unawaited(_load()),
    );
    final hosts =
        ref.watch(desktopServerCatalogProvider).valueOrNull?.hosts ?? [];
    final scripts =
        ref.watch(desktopTerminalScriptCatalogProvider).valueOrNull?.scripts ??
        [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: ManagementTabs<bool>(
            options: {
              false: mx(context, '任务列表', 'Tasks'),
              true: mx(context, '执行历史', 'Execution history'),
            },
            value: _history,
            onChanged: (history) {
              setState(() => _history = history);
              _load();
            },
          ),
        ),
        Expanded(
          child: ManagementPage(
            tableSpacing: 14,
            busy: _loading || _busy,
            error: _error,
            toolbar: _history ? _historyToolbar() : _taskToolbar(),
            footer: !_history
                ? null
                : ManagementPagination(
                    total: _runs?.total ?? 0,
                    page: _page,
                    pageSize: _size,
                    onPage: (v) {
                      _page = v;
                      _load();
                    },
                    onPageSize: (v) {
                      _size = v;
                      _page = 1;
                      _load();
                    },
                  ),
            child: _history
                ? ManagementTable(
                    empty: mx(context, '暂无执行记录', 'No execution records'),
                    onRowTap: (index) => _openRun(_runs!.items[index]),
                    columns: [
                      ManagementColumn(mx(context, '任务', 'Task'), width: 180),
                      ManagementColumn(
                        mx(context, '触发', 'Trigger'),
                        width: 100,
                      ),
                      ManagementColumn(mx(context, '状态', 'Status'), width: 116),
                      ManagementColumn(mx(context, '主机', 'Hosts'), width: 110),
                      ManagementColumn(
                        mx(context, '开始时间', 'Started'),
                        width: 170,
                      ),
                      ManagementColumn(
                        mx(context, '耗时', 'Duration'),
                        width: 112,
                      ),
                      ManagementColumn.actions(
                        mx(context, '操作', 'Actions'),
                        width: 90,
                      ),
                    ],
                    rows: [
                      for (final r in _runs?.items ?? <ScheduledTaskRun>[])
                        [
                          Text(r.taskName),
                          Text(
                            r.trigger == 'manual'
                                ? mx(context, '手动', 'Manual')
                                : mx(context, '计划', 'Scheduled'),
                          ),
                          _status(r.status),
                          Text(
                            mx(
                              context,
                              '${r.targetCount} 台',
                              '${r.targetCount} hosts',
                            ),
                          ),
                          Text(managementDate(r.startedAt)),
                          Text(formatTaskDuration(r.durationMs)),
                          ManagementLink(
                            label: mx(context, '详情', 'Details'),
                            onPressed: () => _openRun(r),
                          ),
                        ],
                    ],
                  )
                : ManagementTable(
                    empty: mx(context, '暂无定时任务', 'No scheduled tasks'),
                    columns: [
                      ManagementColumn(mx(context, '任务', 'Task'), width: 190),
                      ManagementColumn(mx(context, '启用', 'Enabled'), width: 76),
                      ManagementColumn(
                        mx(context, '计划', 'Schedule'),
                        width: 180,
                      ),
                      ManagementColumn(
                        mx(context, '目标', 'Targets'),
                        width: 160,
                      ),
                      ManagementColumn(
                        mx(context, '指令', 'Command'),
                        width: 130,
                      ),
                      ManagementColumn(
                        mx(context, '下次执行', 'Next run'),
                        width: 170,
                      ),
                      ManagementColumn(
                        mx(context, '最近结果', 'Last result'),
                        width: 112,
                      ),
                      ManagementColumn(mx(context, '通知', 'Notify'), width: 92),
                      ManagementColumn.actions(
                        mx(context, '操作', 'Actions'),
                        width: 210,
                      ),
                    ],
                    rows: [
                      for (final t in _tasks)
                        [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (t.disabledReason.isNotEmpty)
                                Text(
                                  t.disabledReason,
                                  style: TextStyle(
                                    color: context.colors.warning,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          ManagementSwitch(
                            value: t.enabled,
                            label: t.name,
                            onChanged: _busy
                                ? null
                                : (v) => _action(() async {
                                    final form = ScheduledTaskFormData.fromTask(
                                      await ref
                                          .read(scheduledTaskRepositoryProvider)
                                          .fetchTask(t.id),
                                    )..enabled = v;
                                    await ref
                                        .read(scheduledTaskRepositoryProvider)
                                        .updateTask(form);
                                  }),
                          ),
                          Tooltip(
                            message: t.nextRunTimes
                                .map(
                                  (d) => formatTaskDate(
                                    d,
                                    timezoneName: t.timezone,
                                  ),
                                )
                                .join('\n'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.cron,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  t.timezone,
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: t.hostIds
                                .map(
                                  (id) =>
                                      hosts
                                          .where((h) => h.id == id)
                                          .firstOrNull
                                          ?.displayName ??
                                      id,
                                )
                                .join('\n'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mx(
                                    context,
                                    '${t.hostIds.length} 台主机',
                                    '${t.hostIds.length} hosts',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mx(
                                    context,
                                    '超时 ${t.timeoutSeconds} 秒',
                                    'Timeout ${t.timeoutSeconds}s',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            t.script.isLibrary
                                ? scripts
                                          .where(
                                            (s) => s.id == t.script.scriptId,
                                          )
                                          .firstOrNull
                                          ?.name ??
                                      t.script.scriptId
                                : mx(context, '独立指令', 'Inline command'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            formatTaskDate(
                              t.nextRunAt,
                              timezoneName: t.timezone,
                            ),
                          ),
                          t.lastRunStatus.isEmpty
                              ? const Text('—')
                              : _status(t.lastRunStatus),
                          Text(
                            t.notificationPolicy == 'always'
                                ? mx(context, '每次', 'Always')
                                : t.notificationPolicy == 'never'
                                ? mx(context, '从不', 'Never')
                                : mx(context, '仅失败', 'On failure'),
                          ),
                          Row(
                            children: [
                              ManagementLink(
                                label: mx(context, '执行', 'Run'),
                                onPressed: _busy ? null : () => _run(t),
                              ),
                              ManagementLink(
                                label: mx(context, '编辑', 'Edit'),
                                onPressed: _busy ? null : () => _edit(t),
                              ),
                              DesktopDropdownMenu<String>(
                                tooltip: mx(context, '更多操作', 'More actions'),
                                buttonSize: const Size(28, 30),
                                items: [
                                  DesktopDropdownItem(
                                    value: 'history',
                                    label: mx(
                                      context,
                                      '执行历史',
                                      'Execution history',
                                    ),
                                    icon: Icons.history,
                                  ),
                                  DesktopDropdownItem(
                                    value: 'delete',
                                    label: mx(context, '删除任务', 'Delete task'),
                                    icon: Icons.delete_outline,
                                    danger: true,
                                  ),
                                ],
                                onSelected: (v) async {
                                  if (v == 'history') {
                                    setState(() {
                                      _history = true;
                                      _taskFilter = t.id;
                                      _page = 1;
                                    });
                                    _load();
                                  } else if (await managementConfirm(
                                        context,
                                        mx(
                                          context,
                                          '确认删除任务「${t.name}」？',
                                          'Delete task ${t.name}?',
                                        ),
                                      ) &&
                                      mounted) {
                                    _action(
                                      () => ref
                                          .read(scheduledTaskRepositoryProvider)
                                          .deleteTask(t.id),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class DesktopScheduledTaskDialog extends ConsumerStatefulWidget {
  const DesktopScheduledTaskDialog({super.key, this.task});
  final ScheduledTask? task;
  @override
  ConsumerState<DesktopScheduledTaskDialog> createState() =>
      _DesktopScheduledTaskDialogState();
}

class _DesktopScheduledTaskDialogState
    extends ConsumerState<DesktopScheduledTaskDialog> {
  final _key = GlobalKey<FormState>();
  late final ScheduledTaskFormData _form = widget.task == null
      ? (ScheduledTaskFormData.create()..cron = '0 2 * * *')
      : ScheduledTaskFormData.fromTask(widget.task!);
  late final _name = TextEditingController(text: _form.name),
      _cron = TextEditingController(text: _form.cron),
      _timezone = TextEditingController(text: _form.timezone),
      _timeout = TextEditingController(text: '${_form.timeoutSeconds}'),
      _command = TextEditingController(text: _form.script.command);
  late bool _reference = _form.script.isLibrary,
      _base64 = _form.script.useBase64;
  late String _scriptId = _form.script.scriptId;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _cron, _timezone, _timeout, _command]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _form
        ..name = _name.text
        ..cron = _cron.text
        ..timezone = _timezone.text.trim()
        ..timeoutSeconds = int.parse(_timeout.text)
        ..script = _reference
            ? ScheduledTaskScript(type: 'library', scriptId: _scriptId)
            : ScheduledTaskScript(
                type: 'inline',
                command: _command.text,
                useBase64: _base64,
              );
      final repo = ref.read(scheduledTaskRepositoryProvider);
      if (_form.isEdit) {
        await repo.updateTask(_form);
      } else {
        await repo.createTask(_form);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _text(
    String label,
    TextEditingController c, {
    String? Function(String?)? validator,
    int lines = 1,
  }) => ManagementField(
    label: label,
    child: TextFormField(
      controller: c,
      enabled: !_busy,
      maxLines: lines,
      decoration: desktopInputDecoration(context),
      style: TextStyle(
        fontSize: 13,
        fontFamily: lines > 1 ? 'monospace' : null,
      ),
      validator:
          validator ??
          (v) => v!.trim().isEmpty ? mx(context, '此项必填', 'Required') : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final hostsState = ref.watch(desktopServerCatalogProvider);
    final scriptsState = ref.watch(desktopTerminalScriptCatalogProvider);
    final hosts =
        hostsState.valueOrNull?.hosts.where((h) => !h.isWindows).toList() ?? [];
    final scripts = scriptsState.valueOrNull?.scripts ?? [];
    final known = hosts.map((h) => h.id).toSet();
    return DesktopManagementDialog(
      width: 720,
      topAligned: true,
      busy: _busy,
      title: widget.task == null
          ? mx(context, '添加任务', 'Add task')
          : mx(context, '编辑任务', 'Edit task'),
      body: Form(
        key: _key,
        child: AbsorbPointer(
          absorbing: _busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ManagementError(message: _error!),
              if (hostsState.hasError || scriptsState.hasError)
                ManagementError(
                  message: managementError(
                    hostsState.error ?? scriptsState.error!,
                  ),
                  onRetry: () {
                    ref.invalidate(desktopServerCatalogProvider);
                    ref.invalidate(desktopTerminalScriptCatalogProvider);
                  },
                ),
              ManagementPair(
                left: _text(
                  mx(context, '任务名称', 'Task name'),
                  _name,
                  validator: (v) => v!.trim().isEmpty || v.length > 100
                      ? mx(
                          context,
                          '请输入 1–100 字符的任务名称',
                          'Enter a task name (1–100 characters)',
                        )
                      : null,
                ),
                right: ManagementField(
                  label: mx(context, '目标主机', 'Target hosts'),
                  child: FormField<List<String>>(
                    validator: (_) => _form.hostIds.isEmpty
                        ? mx(context, '至少选择一台主机', 'Select at least one host')
                        : null,
                    builder: (field) => DesktopSelect(
                      options: {
                        for (final h in hosts) h.id: h.displayName,
                        for (final id in _form.hostIds.where(
                          (id) => !known.contains(id),
                        ))
                          id: mx(
                            context,
                            '不可用主机 ($id)',
                            'Unavailable host ($id)',
                          ),
                      },
                      values: _form.hostIds,
                      errorText: field.errorText,
                      onSelected: (v) => setState(() => _form.hostIds.add(v)),
                      onRemoved: (v) => setState(() => _form.hostIds.remove(v)),
                    ),
                  ),
                ),
              ),
              ManagementPair(
                left: ManagementField(
                  label: mx(
                    context,
                    'Cron（分 时 日 月 周）',
                    'Cron (minute hour day month weekday)',
                  ),
                  child: ManagementSuggestionInput(
                    controller: _cron,
                    options: {
                      '* * * * *': mx(context, '每分钟', 'Every minute'),
                      '*/30 * * * *': mx(
                        context,
                        '每 30 分钟',
                        'Every 30 minutes',
                      ),
                      '0 * * * *': mx(context, '每小时', 'Every hour'),
                      '0 2 * * *': mx(context, '每天 02:00', 'Daily at 02:00'),
                      '0 0 * * 1': mx(context, '每周一 00:00', 'Mondays at 00:00'),
                      '0 0 1 * *': mx(
                        context,
                        '每月 1 日 00:00',
                        'Monthly on day 1 at 00:00',
                      ),
                    },
                    validator: (v) =>
                        v!.trim().split(RegExp(r'\s+')).length == 5
                        ? null
                        : mx(
                            context,
                            '请输入 5 段 Cron 表达式',
                            'Enter a five-field Cron expression',
                          ),
                  ),
                ),
                right: ManagementField(
                  label: mx(context, '时区', 'Time zone'),
                  child: ManagementSuggestionInput(
                    controller: _timezone,
                    options: {
                      for (final z in [
                        'Asia/Shanghai',
                        'UTC',
                        'Asia/Hong_Kong',
                        'Asia/Tokyo',
                        'Europe/London',
                        'America/New_York',
                      ])
                        z: z,
                    },
                    validator: (v) => v!.trim().isEmpty
                        ? mx(context, '请输入时区', 'Enter a timezone')
                        : null,
                  ),
                ),
              ),
              ManagementPair(
                left: _text(
                  mx(context, '超时（秒）', 'Timeout (seconds)'),
                  _timeout,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 1800
                        ? mx(context, '范围为 1–1800 秒', 'Range: 1–1800 seconds')
                        : null;
                  },
                ),
                right: ManagementField(
                  label: mx(context, '执行通知', 'Notifications'),
                  child: DesktopSelect(
                    options: {
                      'failure': mx(context, '仅失败时', 'On failure'),
                      'always': mx(context, '每次执行', 'Every execution'),
                      'never': mx(context, '从不通知', 'Never'),
                    },
                    values: [_form.notificationPolicy],
                    onSelected: (v) =>
                        setState(() => _form.notificationPolicy = v),
                  ),
                ),
              ),
              if (!_reference)
                ManagementField(
                  label: mx(context, '执行方式', 'Execution mode'),
                  child: Wrap(
                    spacing: 0,
                    children: [
                      for (final mode in [false, true])
                        ManagementButton(
                          label: mode
                              ? mx(context, 'Base64 脚本', 'Base64 script')
                              : mx(context, '直接执行', 'Direct'),
                          primary: _base64 == mode,
                          onPressed: () => setState(() => _base64 = mode),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: !_reference
                          ? DesktopScriptImportButton(
                              scripts: scripts,
                              onSelected: (s) => setState(() {
                                _command.text = s.command;
                                _base64 = s.useBase64;
                              }),
                            )
                          : Text(
                              mx(context, '指令', 'Command'),
                              style: const TextStyle(fontSize: 13),
                            ),
                    ),
                  ),
                  Text(
                    mx(context, '引用脚本库', 'Reference library script'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  ManagementSwitch(
                    value: _reference,
                    label: mx(context, '引用脚本库', 'Reference library script'),
                    onChanged: (v) => setState(() => _reference = v),
                  ),
                ],
              ),
              if (_reference)
                FormField<String>(
                  validator: (_) => scripts.any((s) => s.id == _scriptId)
                      ? null
                      : mx(context, '请选择脚本库脚本', 'Select a library script'),
                  builder: (field) => DesktopSelect(
                    options: {for (final s in scripts) s.id: s.name},
                    values: _scriptId.isEmpty ? [] : [_scriptId],
                    errorText: field.errorText,
                    onSelected: (v) => setState(() => _scriptId = v),
                  ),
                )
              else ...[
                _text(
                  mx(context, 'Shell 指令', 'Shell command'),
                  _command,
                  lines: 12,
                  validator: (v) =>
                      v!.trim().isEmpty || utf8.encode(v).length > 256 * 1024
                      ? mx(
                          context,
                          '脚本不能为空，且不能超过 256 KiB',
                          'Script must not be empty or exceed 256 KiB',
                        )
                      : null,
                ),
                ValueListenableBuilder(
                  valueListenable: _command,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${utf8.encode(value.text).length} B / 256 KiB',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ),
              ],
              Row(
                children: [
                  ManagementSwitch(
                    value: _form.enabled,
                    label: mx(context, '启用任务', 'Enable task'),
                    onChanged: (v) => setState(() => _form.enabled = v),
                  ),
                  Text(
                    mx(context, '启用任务', 'Enable task'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        ManagementButton(
          label: mx(context, '取消', 'Cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        ManagementButton(
          label: mx(context, '保存', 'Save'),
          primary: true,
          onPressed: _busy || hostsState.isLoading || scriptsState.isLoading
              ? null
              : _save,
        ),
      ],
    );
  }
}

class DesktopScheduledRunDetail extends ConsumerStatefulWidget {
  const DesktopScheduledRunDetail({super.key, required this.runId});
  final String runId;
  @override
  ConsumerState<DesktopScheduledRunDetail> createState() =>
      _DesktopScheduledRunDetailState();
}

class _DesktopScheduledRunDetailState
    extends ConsumerState<DesktopScheduledRunDetail> {
  ScheduledTaskRun? _run;
  Timer? _timer;
  String? _error;
  bool _stopping = false;
  final _expanded = <String>{};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    try {
      final run = await ref
          .read(scheduledTaskRepositoryProvider)
          .fetchRun(widget.runId);
      if (mounted) {
        setState(() {
          _run = run;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    }
    if (mounted && (_run == null || !_run!.isComplete)) {
      _timer = Timer(const Duration(seconds: 3), _load);
    }
  }

  Future<void> _stop() async {
    if (!await managementConfirm(
          context,
          mx(context, '停止整批执行？', 'Stop the entire batch?'),
        ) ||
        !mounted) {
      return;
    }
    setState(() => _stopping = true);
    try {
      await ref.read(scheduledTaskRepositoryProvider).stopRun(widget.runId);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Widget _runSummary(ScheduledTaskRun run) {
    final fields = <(String, Widget)>[
      (mx(context, '任务', 'Task'), Text(run.taskName)),
      (
        mx(context, '状态', 'Status'),
        ManagementTag(
          scheduledTaskStatusLabel(AppLocalizations.of(context), run.status),
          color: scheduledTaskStatusColor(context, run.status),
        ),
      ),
      (
        mx(context, '触发', 'Trigger'),
        Text(run.trigger == 'manual' ? mx(context, '手动执行', 'Manual') : 'Cron'),
      ),
      (mx(context, '耗时', 'Duration'), Text(formatTaskDuration(run.durationMs))),
    ];
    return LayoutBuilder(
      builder: (context, size) => Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: Wrap(
          children: [
            for (final field in fields)
              SizedBox(
                width: size.maxWidth / (size.maxWidth < 600 ? 2 : 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.$1,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        child: field.$2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _targetOutput(String label, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.muted)),
      Container(
        constraints: const BoxConstraints(minHeight: 92, maxHeight: 420),
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(top: 6, bottom: 12),
        decoration: BoxDecoration(
          color: context.colors.chip,
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? mx(context, '(无输出)', '(No output)') : text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  mx(context, '执行详情', 'Execution details'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: mx(context, '关闭', 'Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  ManagementError(message: _error!, onRetry: _load),
                if (run == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _runSummary(run),
                  if (run.reason.isNotEmpty || run.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${run.reason}\n${run.error}',
                        style: TextStyle(
                          color: context.colors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (run.isRunning)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ManagementLink(
                        label: _stopping
                            ? mx(context, '停止中…', 'Stopping…')
                            : mx(context, '停止整批', 'Stop batch'),
                        danger: true,
                        onPressed: _stopping ? null : _stop,
                      ),
                    ),
                  const SizedBox(height: 20),
                  for (final target in run.targets)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () => setState(() {
                              if (!_expanded.add(target.id)) {
                                _expanded.remove(target.id);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(
                                    _expanded.contains(target.id)
                                        ? Icons.expand_more
                                        : Icons.chevron_right,
                                    size: 16,
                                  ),
                                  Text(target.hostName),
                                  ManagementTag(
                                    scheduledTaskStatusLabel(
                                      AppLocalizations.of(context),
                                      target.status,
                                    ),
                                    color: scheduledTaskStatusColor(
                                      context,
                                      target.status,
                                    ),
                                  ),
                                  Text(formatTaskDuration(target.durationMs)),
                                  if (target.truncated)
                                    Text(
                                      mx(
                                        context,
                                        '输出已截断至 256 KiB',
                                        'Output truncated at 256 KiB',
                                      ),
                                      style: TextStyle(
                                        color: context.colors.warning,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (target.exitCode != null)
                                    Text(
                                      'exit ${target.exitCode}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_expanded.contains(target.id))
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (target.error.isNotEmpty)
                                    Text(
                                      target.error,
                                      style: TextStyle(
                                        color: context.colors.danger,
                                      ),
                                    ),
                                  if (target.timeoutPhase.isNotEmpty)
                                    Text(
                                      '${mx(context, '超时阶段', 'Timeout phase')}: ${target.timeoutPhase}',
                                    ),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final outputs = [
                                        _targetOutput('stdout', target.stdout),
                                        _targetOutput('stderr', target.stderr),
                                      ];
                                      return constraints.maxWidth < 520
                                          ? Column(children: outputs)
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(child: outputs[0]),
                                                const SizedBox(width: 12),
                                                Expanded(child: outputs[1]),
                                              ],
                                            );
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
