import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../terminal/desktop/terminal_widgets.dart';
import '../ai_agent/agent_models.dart';
import 'file_transfer_client.dart';

class DesktopTransferTasks extends StatefulWidget {
  const DesktopTransferTasks({super.key, required this.client});
  final FileTransferClient client;
  @override
  State<DesktopTransferTasks> createState() => _DesktopTransferTasksState();
}

class _DesktopTransferTasksState extends State<DesktopTransferTasks> {
  String _filter = 'all';
  final _expanded = <String>{};
  String _status(String status) => switch (status) {
    'running' => mx(context, '传输中', 'Running'),
    'completed' => mx(context, '传输完成', 'Completed'),
    'failed' => mx(context, '传输失败', 'Failed'),
    'cancelled' => mx(context, '已取消', 'Cancelled'),
    _ => status,
  };
  Color _color(String status) => switch (status) {
    'running' => context.colors.accent,
    'completed' => context.colors.success,
    'failed' => context.colors.danger,
    _ => context.colors.muted,
  };
  Future<void> _action(String event, [String? id]) async {
    if ([
      'delete_task',
      'clear_completed_tasks',
      'cancel_task',
    ].contains(event)) {
      if (!await managementConfirm(
            context,
            mx(
              context,
              event == 'delete_task'
                  ? '删除此传输任务？'
                  : event == 'cancel_task'
                  ? '取消此传输任务？'
                  : '清空已完成、失败和取消的任务？',
              event == 'delete_task'
                  ? 'Delete this transfer task?'
                  : event == 'cancel_task'
                  ? 'Cancel this transfer task?'
                  : 'Clear completed, failed and cancelled tasks?',
            ),
          ) ||
          !mounted) {
        return;
      }
    }
    widget.client.action(event, id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) {
      final client = widget.client;
      final tasks = client.tasks
          .where((t) => _filter == 'all' || t['status'] == _filter)
          .toList();
      return DesktopManagementDialog(
        width: MediaQuery.sizeOf(context).width * .8,
        title: mx(context, '传输任务管理', 'Transfer tasks'),
        body: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final status in [
                        'all',
                        'running',
                        'completed',
                        'failed',
                        'cancelled',
                      ])
                        _filterButton(status),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (client.error != null) ManagementError(message: client.error!),
              Expanded(
                child: tasks.isEmpty
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TerminalIcon(
                                Icons.article_outlined,
                                size: 48,
                                color: context.colors.softMuted,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _filter == 'all'
                                    ? mx(context, '暂无传输任务', 'No transfer tasks')
                                    : mx(
                                        context,
                                        '暂无${_status(_filter)}的任务',
                                        'No ${_status(_filter).toLowerCase()} tasks',
                                      ),
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _task(tasks[i]),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          ManagementButton(
            height: 32,
            label: mx(context, '关闭', 'Close'),
            onPressed: () => Navigator.pop(context),
          ),
          ManagementButton(
            height: 32,
            label: mx(context, '清空任务列表', 'Clear finished tasks'),
            danger: true,
            onPressed: client.connected
                ? () => _action('clear_completed_tasks')
                : null,
          ),
        ],
      );
    },
  );
  Widget _task(Map<String, dynamic> task) {
    final id = '${task['taskId']}';
    final status = '${task['status']}';
    final client = widget.client;
    final enabled = client.connected && !client.pending.contains(id);
    final progress = (double.tryParse('${task['progress']}') ?? 0)
        .clamp(0, 100)
        .toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ['running', 'completed', 'failed'].contains(status)
            ? _color(status).withValues(alpha: .08)
            : context.colors.card,
        border: Border.all(
          color: ['running', 'completed', 'failed'].contains(status)
              ? _color(status).withValues(alpha: .3)
              : context.colors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${task['sourceHostName']} → ${task['targetHostName']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ManagementTag(_status(status), color: _color(status)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.chip,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${task['method'] ?? 'rsync'}'.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                      Text(
                        managementDate(_date(task['createTime'])),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (status == 'running')
                    ManagementButton(
                      height: 24,
                      label: mx(context, '取消', 'Cancel'),
                      danger: true,
                      onPressed: enabled
                          ? () => _action('cancel_task', id)
                          : null,
                    ),
                  if (status == 'failed')
                    ManagementButton(
                      height: 24,
                      label: mx(context, '重试', 'Retry'),
                      primary: true,
                      onPressed: enabled
                          ? () => _action('retry_task', id)
                          : null,
                    ),
                  if (status != 'running')
                    ManagementButton(
                      height: 24,
                      label: mx(context, '删除', 'Delete'),
                      danger: true,
                      onPressed: enabled
                          ? () => _action('delete_task', id)
                          : null,
                    ),
                  ManagementButton(
                    height: 24,
                    label: _expanded.contains(id)
                        ? mx(context, '收起', 'Collapse')
                        : mx(context, '详情', 'Details'),
                    onPressed: () => setState(() {
                      if (!_expanded.add(id)) _expanded.remove(id);
                    }),
                  ),
                ],
              ),
            ],
          ),
          if (status == 'running') ...[
            const SizedBox(height: 14),
            if (task['isVerifying'] == true)
              Text(
                mx(context, '传输完成，校验中…', 'Transfer finished, verifying…'),
                style: TextStyle(fontSize: 12, color: context.colors.warning),
              )
            else
              DefaultTextStyle(
                style: TextStyle(fontSize: 12, color: context.colors.muted),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${mx(context, '总体进度', 'Progress')}: ${progress.toStringAsFixed(0)}%',
                    ),
                    if (task['fileProgress'] != null)
                      Text(
                        '${mx(context, '文件进度', 'Files')}: ${task['completedFiles'] ?? 0}/${task['totalFiles'] ?? 1}',
                      ),
                    if (task['speed'] != null)
                      Text(
                        '${mx(context, '速度', 'Speed')}: ${_size(task['speed'])}/s',
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task['isVerifying'] == true ? null : progress / 100,
              minHeight: 9,
              color: task['isVerifying'] == true
                  ? context.colors.warning
                  : context.colors.accent,
              backgroundColor: context.colors.chip,
              borderRadius: BorderRadius.circular(5),
            ),
            if (task['isVerifying'] != true)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    TerminalIcon(
                      Icons.article_outlined,
                      size: 14,
                      color: context.colors.accent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        path.posix.basename('${task['currentFile'] ?? '...'}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (status == 'failed' && task['errorMessage'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ManagementError(message: '${task['errorMessage']}'),
            ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            curve: Curves.easeInOutCubic,
            child: !_expanded.contains(id)
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.colors.border),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _detail(mx(context, '任务 ID', 'Task ID'), Text(id)),
                        _detail(
                          mx(context, '传输方法', 'Method'),
                          Text('${task['method'] ?? 'rsync'}'.toUpperCase()),
                        ),
                        _detail(
                          mx(context, '源路径', 'Source paths'),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final item in mapList(task['sourcePaths']))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        item['type'] == 'd'
                                            ? Icons.folder_outlined
                                            : Icons.article_outlined,
                                        size: 14,
                                        color: context.colors.muted,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '${item['path']}  (${_size(item['size'])})',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _detail(
                          mx(context, '目标路径', 'Destination'),
                          Text('${task['targetPath']}'),
                        ),
                        _detail(
                          mx(context, '总大小', 'Total size'),
                          Text(_size(task['totalSize'])),
                        ),
                        _detail(
                          mx(context, '创建时间', 'Created'),
                          Text(managementDate(_date(task['createTime']))),
                        ),
                        if (task['updateTime'] != null &&
                            task['updateTime'] != task['createTime'])
                          _detail(
                            mx(context, '更新时间', 'Updated'),
                            Text(managementDate(_date(task['updateTime']))),
                          ),
                        if (stringMap(task['options']).isNotEmpty) ...[
                          Text(
                            mx(context, '传输选项', 'Transfer options'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final option in stringMap(
                                task['options'],
                              ).entries)
                                ManagementTag(
                                  '${_optionName(option.key)}: ${option.value == true ? mx(context, '是', 'Yes') : mx(context, '否', 'No')}',
                                  color: option.value == true
                                      ? context.colors.success
                                      : context.colors.muted,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, Widget value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DefaultTextStyle(
      style: TextStyle(fontSize: 13, height: 1.5, color: context.colors.text),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: context.colors.muted,
              ),
            ),
          ),
          Expanded(child: SelectionArea(child: value)),
        ],
      ),
    ),
  );

  String _optionName(String key) => switch (key) {
    'delete' => mx(context, '删除目标多余文件', 'Delete extra files'),
    'partial' => mx(context, '断点续传', 'Resume transfers'),
    'compress' => mx(context, '压缩传输', 'Compression'),
    _ => key,
  };

  Widget _filterButton(String status) {
    final active = _filter == status;
    final first = status == 'all', last = status == 'cancelled';
    return Semantics(
      selected: active,
      child: TextButton(
        onPressed: () => setState(() => _filter = status),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          splashFactory: NoSplash.splashFactory,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => active
                ? context.colors.fontOnPrimary
                : states.contains(WidgetState.hovered)
                ? context.colors.accent
                : context.colors.text,
          ),
          backgroundColor: WidgetStatePropertyAll(
            active ? context.colors.accent : context.colors.card,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(first ? 4 : 0),
                right: Radius.circular(last ? 4 : 0),
              ),
            ),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: active ? context.colors.accent : context.colors.border,
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          ),
        ),
        child: Text(first ? mx(context, '全部', 'All') : _status(status)),
      ),
    );
  }

  DateTime? _date(Object? value) => intValue(value) > 0
      ? DateTime.fromMillisecondsSinceEpoch(intValue(value))
      : null;
  String _size(Object? raw) {
    var value = double.tryParse('$raw') ?? 0;
    var unit = 0;
    while (value >= 1024 && unit < 4) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${['B', 'KB', 'MB', 'GB', 'TB'][unit]}';
  }
}
