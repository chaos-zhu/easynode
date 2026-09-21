import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_overflow_menu.dart';
import '../../core/ui/app_swipe_actions.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/scheduled_task_notifier.dart';
import '../shell/tab_header.dart';
import 'scheduled_task_form_page.dart';
import 'scheduled_task_models.dart';
import 'scheduled_task_run_detail_page.dart';
import 'scheduled_task_runs_page.dart';
import 'scheduled_task_ui.dart';

class ScheduledTasksTab extends ConsumerStatefulWidget {
  const ScheduledTasksTab({super.key});

  @override
  ConsumerState<ScheduledTasksTab> createState() => _ScheduledTasksTabState();
}

class _ScheduledTasksTabState extends ConsumerState<ScheduledTasksTab> {
  final _searchController = TextEditingController();
  final _swipeActionsController = AppSwipeActionsController();
  final _busyTaskIds = <String>{};
  String? _expandedTaskId;
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    _swipeActionsController.dispose();
    super.dispose();
  }

  void _toggleDetails(String id) {
    _swipeActionsController.close();
    setState(() {
      _expandedTaskId = _expandedTaskId == id ? null : id;
    });
  }

  Future<void> _refresh() {
    return ref
        .read(scheduledTaskListProvider.notifier)
        .refresh(throwOnError: true);
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScheduledTaskFormPage()),
    );
  }

  Future<void> _openEdit(ScheduledTask task) async {
    setState(() => _busyTaskIds.add(task.id));
    try {
      final detail = await ref
          .read(scheduledTaskRepositoryProvider)
          .fetchTask(task.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduledTaskFormPage(task: detail),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyTaskIds.remove(task.id));
    }
  }

  Future<void> _openHistory({ScheduledTask? task}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScheduledTaskRunsPage(taskId: task?.id, taskName: task?.name),
      ),
    );
    await ref.read(scheduledTaskListProvider.notifier).refresh();
  }

  Future<void> _run(ScheduledTask task) async {
    final l = AppLocalizations.of(context);
    setState(() => _busyTaskIds.add(task.id));
    try {
      final run = await ref
          .read(scheduledTaskRepositoryProvider)
          .runTask(task.id);
      await ref.read(scheduledTaskListProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('scheduledTasks.runSubmitted'))),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduledTaskRunDetailPage(runId: run.id),
        ),
      );
      await ref.read(scheduledTaskListProvider.notifier).refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyTaskIds.remove(task.id));
    }
  }

  Future<void> _toggle(ScheduledTask task, bool enabled) async {
    setState(() => _busyTaskIds.add(task.id));
    try {
      await ref
          .read(scheduledTaskListProvider.notifier)
          .setEnabled(task, enabled);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyTaskIds.remove(task.id));
    }
  }

  Future<void> _delete(ScheduledTask task) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('scheduledTasks.deleteTask')),
        content: Text(l.trf('scheduledTasks.deleteConfirm', [task.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
            ),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyTaskIds.add(task.id));
    try {
      await ref.read(scheduledTaskListProvider.notifier).delete(task.id);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyTaskIds.remove(task.id));
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  List<ScheduledTask> _filtered(List<ScheduledTask> tasks) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return tasks;
    return tasks
        .where(
          (task) => [
            task.name,
            task.cron,
            task.timezone,
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  void _toggleSearch() {
    _swipeActionsController.close();
    setState(() {
      _expandedTaskId = null;
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tasks = ref.watch(scheduledTaskListProvider);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: Column(
        children: [
          TabHeader(
            title: l.tr('tabs.scheduledTasks'),
            actions: [
              IconButton(
                tooltip: l.tr('scheduledTasks.addTask'),
                onPressed: _openCreate,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 4),
              AppOverflowMenu<String>(
                key: const ValueKey('scheduled-task-more-menu'),
                tooltip: l.tr('common.moreActions'),
                items: [
                  AppOverflowMenuItem(
                    value: 'search',
                    icon: _searchVisible ? Icons.close : Icons.search,
                    label: _searchVisible
                        ? l.tr('common.closeSearch')
                        : l.tr('common.search'),
                  ),
                  AppOverflowMenuItem(
                    value: 'history',
                    icon: Icons.history,
                    label: l.tr('scheduledTasks.history'),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'search') {
                    _toggleSearch();
                  } else if (action == 'history') {
                    _openHistory();
                  }
                },
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _searchVisible
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      key: const ValueKey('scheduled-task-search-field'),
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l.tr('scheduledTasks.searchHint'),
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: context.colors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _TaskError(error: error, onRetry: _refresh),
              data: (items) {
                final filtered = _filtered(items);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 160),
                            Center(
                              child: Text(
                                items.isEmpty
                                    ? l.tr('scheduledTasks.empty')
                                    : l.tr('scheduledTasks.emptyFiltered'),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final task = filtered[index];
                            return _TaskCard(
                              task: task,
                              busy: _busyTaskIds.contains(task.id),
                              expanded: _expandedTaskId == task.id,
                              swipeActionsController: _swipeActionsController,
                              onToggleDetails: () => _toggleDetails(task.id),
                              onToggle: (value) => _toggle(task, value),
                              onRun: () => _run(task),
                              onEdit: () => _openEdit(task),
                              onHistory: () => _openHistory(task: task),
                              onDelete: () => _delete(task),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.busy,
    required this.expanded,
    required this.swipeActionsController,
    required this.onToggleDetails,
    required this.onToggle,
    required this.onRun,
    required this.onEdit,
    required this.onHistory,
    required this.onDelete,
  });

  final ScheduledTask task;
  final bool busy;
  final bool expanded;
  final AppSwipeActionsController swipeActionsController;
  final VoidCallback onToggleDetails;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      key: ValueKey('scheduled-task-${task.id}'),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? context.colors.strongBorder : context.colors.border,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: context.colors.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSwipeActions(
              key: ValueKey('scheduled-task-swipe-${task.id}'),
              itemId: task.id,
              controller: swipeActionsController,
              actions: [
                AppSwipeAction(
                  key: ValueKey('scheduled-task-action-edit-${task.id}'),
                  icon: Icons.edit_outlined,
                  label: l.tr('common.edit'),
                  tone: AppSwipeActionTone.primary,
                  onPressed: onEdit,
                ),
                AppSwipeAction(
                  key: ValueKey('scheduled-task-action-delete-${task.id}'),
                  icon: Icons.delete_outline,
                  label: l.tr('common.delete'),
                  tone: AppSwipeActionTone.danger,
                  onPressed: onDelete,
                ),
              ],
              child: SizedBox(
                height: 72,
                child: Semantics(
                  button: true,
                  expanded: expanded,
                  child: InkWell(
                    key: ValueKey('scheduled-task-summary-${task.id}'),
                    onTap: onToggleDetails,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.colors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Flexible(
                                      child: _Meta(
                                        icon: Icons.schedule,
                                        text: task.cron,
                                        monospace: true,
                                      ),
                                    ),
                                    if (task.lastRunStatus.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      ScheduledTaskStatusChip(
                                        status: task.lastRunStatus,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width: 46,
                              height: 40,
                              child: Center(
                                child: Transform.scale(
                                  scale: 0.78,
                                  child: Switch(
                                    value: task.enabled,
                                    onChanged: onToggle,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Container(
                      key: ValueKey('scheduled-task-details-${task.id}'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: context.colors.border),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (task.disabledReason.isNotEmpty) ...[
                            Text(
                              task.disabledReason,
                              style: TextStyle(
                                color: context.colors.warning,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final tileWidth = (constraints.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr(
                                        'scheduledTasks.field.timezone',
                                      ),
                                      value: task.timezone,
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr('scheduledTasks.field.hosts'),
                                      value: l.trf('scheduledTasks.hostCount', [
                                        task.hostIds.length,
                                      ]),
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr(
                                        'scheduledTasks.field.command',
                                      ),
                                      value: task.script.isLibrary
                                          ? l.tr(
                                              'scheduledTasks.referenceScript',
                                            )
                                          : task.script.useBase64
                                          ? l.tr('scheduledTasks.base64Script')
                                          : l.tr('scheduledTasks.inlineScript'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr(
                                        'scheduledTasks.field.timeout',
                                      ),
                                      value: '${task.timeoutSeconds}',
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr(
                                        'scheduledTasks.field.notification',
                                      ),
                                      value: l.tr(
                                        'scheduledTasks.notification.${task.notificationPolicy}',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _TaskDetailTile(
                                      label: l.tr(
                                        'scheduledTasks.field.nextRun',
                                      ),
                                      value: formatTaskDate(
                                        task.nextRunAt,
                                        timezoneName: task.timezone,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: l.tr('scheduledTasks.history'),
                                onPressed: onHistory,
                                style: IconButton.styleFrom(
                                  foregroundColor: context.colors.muted,
                                  backgroundColor: context.colors.chip,
                                ),
                                icon: const Icon(Icons.history_rounded),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: l.tr('scheduledTasks.runNow'),
                                onPressed: busy ? null : onRun,
                                style: IconButton.styleFrom(
                                  foregroundColor: context.colors.fontOnPrimary,
                                  backgroundColor: context.colors.primary,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('scheduled-task-details-collapsed'),
                      width: double.infinity,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.monospace = false});

  final IconData icon;
  final String text;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.colors.softMuted),
        const SizedBox(width: 4),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.softMuted,
            fontSize: 12,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}

class _TaskDetailTile extends StatelessWidget {
  const _TaskDetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.chip,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.colors.softMuted, fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskError extends StatelessWidget {
  const _TaskError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l.tr('common.retry'))),
          ],
        ),
      ),
    );
  }
}
