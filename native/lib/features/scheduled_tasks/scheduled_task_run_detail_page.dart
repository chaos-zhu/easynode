import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import 'scheduled_task_models.dart';
import 'scheduled_task_ui.dart';

class ScheduledTaskRunDetailPage extends ConsumerStatefulWidget {
  const ScheduledTaskRunDetailPage({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<ScheduledTaskRunDetailPage> createState() =>
      _ScheduledTaskRunDetailPageState();
}

class _ScheduledTaskRunDetailPageState
    extends ConsumerState<ScheduledTaskRunDetailPage> {
  ScheduledTaskRun? _run;
  Object? _error;
  bool _loading = true;
  bool _stopping = false;
  bool _requestInFlight = false;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_requestInFlight) return;
    _poller?.cancel();
    _poller = null;
    _requestInFlight = true;
    try {
      final run = await ref
          .read(scheduledTaskRepositoryProvider)
          .fetchRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = run;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      _requestInFlight = false;
      if (mounted && _run?.isComplete == false) {
        _poller = Timer(const Duration(seconds: 3), _load);
      }
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      await ref.read(scheduledTaskRepositoryProvider).stopRun(widget.runId);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        title: Text(l.tr('scheduledTasks.runDetail')),
        backgroundColor: context.colors.canvas,
        actions: [
          IconButton(
            tooltip: l.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _run == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _run == null
          ? _ErrorBody(error: _error!, onRetry: _load)
          : _RunBody(run: _run!, stopping: _stopping, onStop: _stop),
    );
  }
}

class _RunBody extends StatelessWidget {
  const _RunBody({
    required this.run,
    required this.stopping,
    required this.onStop,
  });

  final ScheduledTaskRun run;
  final bool stopping;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              _SummaryRow(
                label: l.tr('scheduledTasks.field.task'),
                value: run.taskName,
              ),
              _SummaryRow(
                label: l.tr('scheduledTasks.field.status'),
                trailing: ScheduledTaskStatusChip(status: run.status),
              ),
              _SummaryRow(
                label: l.tr('scheduledTasks.field.trigger'),
                value: run.trigger == 'manual'
                    ? l.tr('scheduledTasks.trigger.manual')
                    : l.tr('scheduledTasks.trigger.scheduled'),
              ),
              _SummaryRow(
                label: l.tr('scheduledTasks.field.startedAt'),
                value: formatTaskDate(run.startedAt),
              ),
              _SummaryRow(
                label: l.tr('scheduledTasks.field.duration'),
                value: formatTaskDuration(run.durationMs),
                bottom: false,
              ),
            ],
          ),
        ),
        if (run.isRunning) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: stopping ? null : onStop,
            icon: stopping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: Text(l.tr('scheduledTasks.stopRun')),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.danger,
              side: BorderSide(color: context.colors.dangerBorder),
            ),
          ),
        ],
        if (run.error.isNotEmpty || run.reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            run.error.isNotEmpty ? run.error : run.reason,
            style: TextStyle(color: context.colors.danger),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          l.tr('scheduledTasks.hostResults'),
          style: TextStyle(
            color: context.colors.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (run.targets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(l.tr('scheduledTasks.noHostResults'))),
          )
        else
          for (final target in run.targets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TargetResult(target: target),
            ),
      ],
    );
  }
}

class _TargetResult extends StatelessWidget {
  const _TargetResult({required this.target});

  final ScheduledTaskTargetRun target;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          target.hostName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(formatTaskDuration(target.durationMs)),
        trailing: ScheduledTaskStatusChip(status: target.status),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (target.error.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  target.error,
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
            ),
          if (target.truncated)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.tr('scheduledTasks.outputTruncated'),
                  style: TextStyle(color: context.colors.warning, fontSize: 12),
                ),
              ),
            ),
          _OutputBlock(title: 'stdout', value: target.stdout),
          const SizedBox(height: 8),
          _OutputBlock(title: 'stderr', value: target.stderr),
        ],
      ),
    );
  }
}

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: context.colors.softMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value.isEmpty ? '(empty)' : value,
            style: TextStyle(
              color: context.colors.text,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    this.value,
    this.trailing,
    this.bottom = true,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom ? 10 : 0),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: context.colors.softMuted),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  trailing ??
                  Text(
                    value ?? '--',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: context.colors.text),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

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
