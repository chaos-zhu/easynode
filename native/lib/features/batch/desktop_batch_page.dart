import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_dropdown_menu.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/desktop_script_catalog_provider.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../scripts/desktop_script_dialogs.dart';
import 'batch_execution.dart';
import 'batch_repository.dart';

class DesktopBatchPage extends ConsumerStatefulWidget {
  const DesktopBatchPage({super.key});
  @override
  ConsumerState<DesktopBatchPage> createState() => _DesktopBatchPageState();
}

class _DesktopBatchPageState extends ConsumerState<DesktopBatchPage> {
  BatchRecordPage? _history;
  bool _loading = true;
  String? _error;
  int _page = 1, _size = 20, _completed = 0;
  final _expanded = <String>{};
  final _output = <String, String>{};
  final _chunks = <String, BatchOutput>{};
  final _loadingOutput = <String>{};
  final _outputErrors = <String, String>{};
  late final BatchExecution _execution;
  @override
  void initState() {
    super.initState();
    _execution = ref.read(batchExecutionProvider);
    _execution.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _execution.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_completed != _execution.completed) {
      _completed = _execution.completed;
      _page = 1;
      unawaited(_load());
    }
    if (_execution.active) {
      _expanded.addAll(_execution.records.map((r) => r.key));
    }
    setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final history = await ref
          .read(batchRepositoryProvider)
          .fetch(page: _page, pageSize: _size);
      if (!mounted) return;
      setState(() {
        _history = history;
        _page = history.page;
      });
      if (!_execution.active) {
        _execution.records = [];
      }
      for (final row in history.items.where((r) => _expanded.contains(r.key))) {
        unawaited(_loadOutput(row));
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOutput(BatchRecord row, {bool append = false}) async {
    if (row.pending ||
        _loadingOutput.contains(row.id) ||
        (!append && _chunks.containsKey(row.id))) {
      return;
    }
    setState(() {
      _loadingOutput.add(row.id);
      _outputErrors.remove(row.id);
    });
    try {
      final chunk = await ref
          .read(batchRepositoryProvider)
          .output(
            row.id,
            offset: append ? _chunks[row.id]?.nextOffset ?? 0 : 0,
          );
      if (!mounted) return;
      setState(() {
        _output[row.id] = '${append ? _output[row.id] ?? '' : ''}${chunk.text}';
        _chunks[row.id] = chunk;
      });
    } catch (e) {
      if (mounted) setState(() => _outputErrors[row.id] = managementError(e));
    } finally {
      if (mounted) setState(() => _loadingOutput.remove(row.id));
    }
  }

  Future<void> _delete(Object ids) async {
    if (!await managementConfirm(
          context,
          mx(context, '确认删除执行记录？', 'Delete execution records?'),
        ) ||
        !mounted) {
      return;
    }
    try {
      await ref.read(batchRepositoryProvider).delete(ids);
      _chunks.clear();
      _output.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(batchExecutionProvider);
    final rows = [..._execution.records, ...?_history?.items];
    return ManagementPage(
      busy: _loading,
      error: _error ?? _execution.error,
      toolbar: Row(
        children: [
          Expanded(
            child: Text(
              _execution.records.isEmpty
                  ? ''
                  : mx(
                      context,
                      '当前批次 ${_execution.records.length} 条',
                      '${_execution.records.length} in this batch',
                    ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          ManagementButton(
            key: const Key('batch-refresh'),
            label: mx(context, '刷新', 'Refresh'),
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
          ManagementButton(
            label: _execution.active
                ? (_execution.stopping
                      ? mx(context, '停止中…', 'Stopping…')
                      : mx(
                          context,
                          '停止执行（剩余 ${_execution.remaining} 秒）',
                          'Stop (${_execution.remaining}s left)',
                        ))
                : mx(context, '执行指令', 'Execute command'),
            primary: !_execution.active,
            icon: _execution.active ? Icons.pause : Icons.send_outlined,
            onPressed: _execution.stopping
                ? null
                : _execution.active
                ? () async {
                    if (await managementConfirm(
                          context,
                          mx(context, '停止整批执行？', 'Stop the entire batch?'),
                        ) &&
                        mounted) {
                      _execution.stop();
                    }
                  }
                : () => showAppDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const DesktopBatchFormDialog(),
                  ),
          ),
          const SizedBox(width: 8),
          DesktopDropdownMenu<String>(
            tooltip: mx(context, '更多操作', 'More actions'),
            items: [
              DesktopDropdownItem(
                value: 'expand',
                label: _expanded.isEmpty
                    ? mx(context, '展开本页', 'Expand this page')
                    : mx(context, '折叠本页', 'Collapse this page'),
                icon: Icons.unfold_more,
              ),
              DesktopDropdownItem(
                value: 'delete',
                label: mx(context, '删除全部记录', 'Delete all records'),
                icon: Icons.delete_outline,
                danger: true,
                enabled: !_execution.active,
                divided: true,
              ),
            ],
            onSelected: (v) {
              if (v == 'delete') {
                _delete('ALL');
              } else {
                final expand = _expanded.isEmpty;
                setState(() {
                  _expanded.clear();
                  if (expand) _expanded.addAll(rows.map((r) => r.key));
                });
                if (expand) {
                  for (final row in rows) {
                    unawaited(_loadOutput(row));
                  }
                }
              }
            },
          ),
        ],
      ),
      footer: ManagementPagination(
        total: _history?.total ?? 0,
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
      child: ManagementTable(
        empty: mx(context, '暂无执行记录', 'No execution records'),
        columns: [
          const ManagementColumn('', width: 44),
          ManagementColumn(mx(context, '实例', 'Instance'), width: 190),
          ManagementColumn(mx(context, '指令', 'Command'), width: 220),
          ManagementColumn(mx(context, '开始时间', 'Started'), width: 170),
          ManagementColumn(mx(context, '结束时间', 'Ended'), width: 170),
          ManagementColumn(mx(context, '执行结果', 'Result'), width: 120),
          ManagementColumn.actions(mx(context, '操作', 'Actions'), width: 90),
        ],
        rows: [
          for (final r in rows)
            [
              IconButton(
                onPressed: () {
                  setState(() {
                    if (!_expanded.add(r.key)) _expanded.remove(r.key);
                  });
                  if (_expanded.contains(r.key)) unawaited(_loadOutput(r));
                },
                icon: Icon(
                  _expanded.contains(r.key)
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 17,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 28,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${r.host}:${r.port}',
                    style: TextStyle(fontSize: 12, color: context.colors.muted),
                  ),
                ],
              ),
              Tooltip(
                message: r.command,
                child: Text(
                  r.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              Text(managementDate(r.start)),
              Text(managementDate(r.end)),
              ManagementTag(
                r.status,
                color: r.status.contains('成功')
                    ? context.colors.success
                    : r.status.contains('失败')
                    ? context.colors.danger
                    : context.colors.accent,
              ),
              r.canStop && _execution.active
                  ? ManagementLink(
                      label: mx(context, '停止', 'Stop'),
                      danger: true,
                      onPressed: _execution.stoppingHosts.contains(r.hostId)
                          ? null
                          : () => _execution.stop(hostId: r.hostId),
                    )
                  : !r.pending
                  ? ManagementLink(
                      label: mx(context, '删除', 'Delete'),
                      danger: true,
                      onPressed: _execution.active
                          ? null
                          : () => _delete([r.id]),
                    )
                  : const SizedBox.shrink(),
            ],
        ],
        expanded: {
          for (var i = 0; i < rows.length; i++)
            if (_expanded.contains(rows[i].key)) i: _result(rows[i]),
        },
      ),
    );
  }

  Widget _result(BatchRecord r) => Container(
    height: 240,
    padding: const EdgeInsets.all(14),
    color: context.colors.chip,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ManagementOutput(
            key: ValueKey(r.key),
            text: r.pending ? r.output : _output[r.id] ?? '',
          ),
        ),
        if (_loadingOutput.contains(r.id))
          const LinearProgressIndicator(minHeight: 2),
        if (_outputErrors[r.id] != null)
          ManagementError(
            message: _outputErrors[r.id]!,
            onRetry: () => _loadOutput(r, append: true),
          )
        else if (_chunks[r.id]?.hasMore == true)
          Align(
            alignment: Alignment.centerLeft,
            child: ManagementLink(
              label: mx(context, '加载更多输出', 'Load more output'),
              onPressed: () => _loadOutput(r, append: true),
            ),
          ),
      ],
    ),
  );
}

class DesktopBatchFormDialog extends ConsumerStatefulWidget {
  const DesktopBatchFormDialog({super.key});
  @override
  ConsumerState<DesktopBatchFormDialog> createState() =>
      _DesktopBatchFormDialogState();
}

class _DesktopBatchFormDialogState
    extends ConsumerState<DesktopBatchFormDialog> {
  final _command = TextEditingController(),
      _timeout = TextEditingController(text: '120');
  final _form = GlobalKey<FormState>();
  final _hosts = <String>[];
  @override
  void dispose() {
    _command.dispose();
    _timeout.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref
        .read(batchExecutionProvider)
        .start([..._hosts], _command.text, int.parse(_timeout.text));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hostsState = ref.watch(desktopServerCatalogProvider);
    final scriptsState = ref.watch(desktopTerminalScriptCatalogProvider);
    final hosts =
        hostsState.valueOrNull?.hosts.where((h) => h.canConnect).toList() ?? [];
    final scripts = scriptsState.valueOrNull?.scripts ?? [];
    return DesktopManagementDialog(
      width: 600,
      topAligned: true,
      topInsetFraction: .06,
      bodyPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      title: mx(context, '批量下发指令', 'Batch command'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hostsState.hasError)
              ManagementError(
                message: managementError(hostsState.error!),
                onRetry: () => ref.invalidate(desktopServerCatalogProvider),
              ),
            ManagementField(
              label: mx(context, '实例', 'Instances'),
              bottomSpacing: 12,
              child: FormField<List<String>>(
                validator: (_) => _hosts.isEmpty
                    ? mx(context, '请选择实例', 'Select instances')
                    : null,
                builder: (field) => DesktopSelect(
                  key: const Key('batch-hosts'),
                  controlHeight: 36,
                  placeholder: mx(
                    context,
                    '选择要执行指令的实例',
                    'Select instances to run the command',
                  ),
                  selectAll: true,
                  selectAllHint: mx(
                    context,
                    '仅显示已配置 SSH 连接的实例',
                    'Only instances with SSH configured',
                  ),
                  clearable: true,
                  showSelectionOrder: false,
                  options: {for (final h in hosts) h.id: h.displayName},
                  values: _hosts,
                  errorText: field.errorText,
                  onSelected: (v) => setState(() => _hosts.add(v)),
                  onRemoved: (v) => setState(() => _hosts.remove(v)),
                ),
              ),
            ),
            ManagementField(
              label: mx(context, '指令', 'Command'),
              bottomSpacing: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DesktopScriptImportButton(
                      height: 20,
                      scripts: scripts,
                      onSelected: (s) => _command.text = s.command,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('batch-command'),
                    controller: _command,
                    minLines: 5,
                    maxLines: 5,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.55,
                    ),
                    decoration: desktopInputDecoration(
                      context,
                      controlHeight: 36,
                      hint: mx(
                        context,
                        '输入 Shell 指令，例如：ping -c 10 google.com',
                        'Enter a Shell command, e.g. ping -c 10 google.com',
                      ),
                    ),
                    validator: (v) => v!.trim().isEmpty
                        ? mx(context, '请输入指令', 'Enter a command')
                        : null,
                  ),
                ],
              ),
            ),
            ManagementField(
              label: mx(context, '超时时间（秒）', 'Timeout (seconds)'),
              bottomSpacing: 0,
              child: TextFormField(
                controller: _timeout,
                style: const TextStyle(fontSize: 13),
                keyboardType: TextInputType.number,
                decoration: desktopInputDecoration(
                  context,
                  controlHeight: 36,
                  hint: mx(
                    context,
                    '指令执行超时时间，单位秒，超时自动中断',
                    'Timeout in seconds; execution stops when exceeded',
                  ),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1
                      ? mx(
                          context,
                          '请输入大于 0 的秒数',
                          'Enter a positive number of seconds',
                        )
                      : null;
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        ManagementButton(
          label: mx(context, '取消', 'Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        ManagementButton(
          label: mx(context, '开始执行', 'Start execution'),
          primary: true,
          onPressed: hostsState.isLoading ? null : _submit,
        ),
      ],
    );
  }
}
