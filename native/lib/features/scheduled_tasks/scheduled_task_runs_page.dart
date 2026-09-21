import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import 'scheduled_task_models.dart';
import 'scheduled_task_run_detail_page.dart';
import 'scheduled_task_ui.dart';

class ScheduledTaskRunsPage extends ConsumerStatefulWidget {
  const ScheduledTaskRunsPage({super.key, this.taskId, this.taskName});

  final String? taskId;
  final String? taskName;

  @override
  ConsumerState<ScheduledTaskRunsPage> createState() =>
      _ScheduledTaskRunsPageState();
}

class _ScheduledTaskRunsPageState extends ConsumerState<ScheduledTaskRunsPage> {
  ScheduledTaskRunPage? _page;
  Object? _error;
  bool _loading = true;
  bool _clearing = false;
  String? _status;

  static const _statuses = [
    'running',
    'success',
    'partial',
    'failed',
    'timeout',
    'cancelled',
    'skipped',
    'interrupted',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(scheduledTaskRepositoryProvider)
          .fetchRuns(taskId: widget.taskId, status: _status, page: page);
      if (!mounted) return;
      setState(() {
        _page = result;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('scheduledTasks.clearRuns')),
        content: Text(l.tr('scheduledTasks.clearRunsConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.tr('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await ref.read(scheduledTaskRepositoryProvider).clearRuns();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _openRun(ScheduledTaskRun run) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScheduledTaskRunDetailPage(runId: run.id),
      ),
    );
    await _load(page: _page?.page ?? 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        title: Text(widget.taskName ?? l.tr('scheduledTasks.history')),
        backgroundColor: context.colors.canvas,
        actions: [
          if (widget.taskId == null)
            IconButton(
              tooltip: l.tr('scheduledTasks.clearRuns'),
              onPressed: _clearing ? null : _clear,
              icon: _clearing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              children: [
                ChoiceChip(
                  label: Text(l.tr('common.all')),
                  selected: _status == null,
                  onSelected: (_) {
                    setState(() => _status = null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                for (final status in _statuses) ...[
                  ChoiceChip(
                    label: Text(scheduledTaskStatusLabel(l, status)),
                    selected: _status == status,
                    onSelected: (_) {
                      setState(() => _status = status);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
          if ((_page?.total ?? 0) > (_page?.pageSize ?? 20))
            _Pagination(
              page: _page!.page,
              pageSize: _page!.pageSize,
              total: _page!.total,
              loading: _loading,
              onPage: (page) => _load(page: page),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final l = AppLocalizations.of(context);
    if (_loading && _page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _page == null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text('${_error.toString()}\n${l.tr('common.retry')}'),
        ),
      );
    }
    final items = _page?.items ?? const <ScheduledTaskRun>[];
    return RefreshIndicator(
      onRefresh: () => _load(page: _page?.page ?? 1),
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 160),
                Center(child: Text(l.tr('scheduledTasks.emptyRuns'))),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final run = items[index];
                return ListTile(
                  tileColor: context.colors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: context.colors.border),
                  ),
                  title: Text(
                    run.taskName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${formatTaskDate(run.startedAt)}  ·  ${formatTaskDuration(run.durationMs)}',
                  ),
                  trailing: ScheduledTaskStatusChip(status: run.status),
                  onTap: () => _openRun(run),
                );
              },
            ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.loading,
    required this.onPage,
  });

  final int page;
  final int pageSize;
  final int total;
  final bool loading;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = (total / pageSize).ceil();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: loading || page <= 1 ? null : () => onPage(page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('$page / $pages'),
            IconButton(
              onPressed: loading || page >= pages
                  ? null
                  : () => onPage(page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
