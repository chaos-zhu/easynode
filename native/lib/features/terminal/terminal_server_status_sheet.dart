import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/terminal_providers.dart';
import 'server_status_monitor_manager.dart';
import 'server_status_snapshot.dart';
import 'terminal_session.dart';

class TerminalServerStatusSheet extends ConsumerWidget {
  const TerminalServerStatusSheet({super.key, required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(serverStatusMonitorManagerProvider);
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        final entry = monitor.entryForHost(session.config.hostId);
        return _ServerStatusContent(
          session: session,
          entry: entry,
          onStart: () => monitor.startNow(session.config),
          onRefresh: entry == null
              ? null
              : () => monitor.refresh(session.config.hostId),
        );
      },
    );
  }
}

class _ServerStatusContent extends StatelessWidget {
  const _ServerStatusContent({
    required this.session,
    required this.entry,
    required this.onStart,
    required this.onRefresh,
  });

  final TerminalSession session;
  final ServerStatusMonitorEntry? entry;
  final Future<void> Function() onStart;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final currentEntry = entry;
    final snapshot = currentEntry?.snapshot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (currentEntry == null)
          _EmptyState(
            icon: Icons.monitor_heart_outlined,
            title: l.tr('terminal.statusPanel.notStarted'),
            message: l.tr('terminal.statusPanel.notStartedHint'),
            actionLabel: l.tr('terminal.statusPanel.startNow'),
            onAction: onStart,
          )
        else if (snapshot == null)
          _EmptyState(
            icon: Icons.sync_rounded,
            title: _stateText(l, currentEntry.state),
            message:
                currentEntry.lastError ?? l.tr('terminal.statusPanel.waiting'),
            actionLabel: currentEntry.state == ServerStatusMonitorState.error
                ? l.tr('common.retry')
                : null,
            onAction: currentEntry.state == ServerStatusMonitorState.error
                ? onStart
                : null,
          )
        else ...[
          // Uptime row
          _UptimeRow(
            entry: currentEntry,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 12),
          // CPU with progress bar
          _ProgressSection(
            label: l.tr('terminal.statusPanel.cpu'),
            percentage: snapshot.cpuInfo.cpuUsage,
          ),
          const SizedBox(height: 6),
          // Load average with high-load coloring
          _LoadAvgRow(
            label: l.tr('terminal.statusPanel.load'),
            loadAvg: snapshot.cpuInfo.loadAvg,
            cpuCount: snapshot.cpuInfo.cpuCount,
          ),
          const SizedBox(height: 12),
          // Memory with progress bar
          _ProgressSection(
            label: l.tr('terminal.statusPanel.memory'),
            percentage: snapshot.memInfo.usedMemPercentage,
            detail: '${_gb(snapshot.memInfo.usedMemMb)}/${_gb(snapshot.memInfo.totalMemMb)}G',
          ),
          const SizedBox(height: 6),
          // Swap with progress bar
          _ProgressSection(
            label: l.tr('terminal.statusPanel.swap'),
            percentage: snapshot.swapInfo.swapPercentage,
            detail: '${_gb(snapshot.swapInfo.swapUsed)}/${_gb(snapshot.swapInfo.swapTotal)}G',
          ),
          const SizedBox(height: 12),
          // Drives - each with progress bar
          for (var i = 0; i < snapshot.drivesInfo.length; i++) ...[
            _DriveProgressRow(
              drive: snapshot.drivesInfo[i],
              label: snapshot.drivesInfo.length == 1
                  ? l.tr('terminal.statusPanel.disk')
                  : l.trf('terminal.statusPanel.diskIndex', ['${i + 1}']),
            ),
            if (i < snapshot.drivesInfo.length - 1) const SizedBox(height: 6),
          ],
          if (snapshot.drivesInfo.isEmpty)
            _ProgressSection(
              label: l.tr('terminal.statusPanel.disk'),
              percentage: 0,
              detail: '--',
            ),
          const SizedBox(height: 12),
          // Network
          _NetworkSection(netstatInfo: snapshot.netstatInfo),
          const SizedBox(height: 12),
          // System info
          _SectionCard(
            title: l.tr('terminal.statusPanel.system'),
            children: [
              _InfoRow(
                label: l.tr('terminal.statusPanel.hostname'),
                value: snapshot.osInfo.hostname,
              ),
              _InfoRow(
                label: l.tr('terminal.statusPanel.cores'),
                value: '${snapshot.cpuInfo.cpuCount}',
              ),
              _InfoRow(
                label: l.tr('terminal.statusPanel.cpuModel'),
                value: snapshot.cpuInfo.cpuModel,
              ),
              _InfoRow(
                label: l.tr('terminal.statusPanel.os'),
                value:
                    '${snapshot.osInfo.type} ${snapshot.osInfo.release} ${snapshot.osInfo.arch}',
              ),
            ],
          ),
          if (currentEntry.lastError != null) ...[
            const SizedBox(height: 12),
            Text(
              currentEntry.lastError!,
              style: TextStyle(color: c.danger, fontSize: 12),
            ),
          ],
        ],
      ],
    );
  }
}

class _UptimeRow extends StatefulWidget {
  const _UptimeRow({required this.entry, required this.onRefresh});

  final ServerStatusMonitorEntry entry;
  final Future<void> Function()? onRefresh;

  @override
  State<_UptimeRow> createState() => _UptimeRowState();
}

class _UptimeRowState extends State<_UptimeRow> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing || widget.onRefresh == null) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh!();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final snapshot = widget.entry.snapshot;
    return Row(
      children: [
        _StatusDot(state: widget.entry.state),
        const SizedBox(width: 8),
        Text(
          '${l.tr('terminal.statusPanel.uptime')}: ',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        Text(
          snapshot != null ? _formatDuration(snapshot.osInfo.uptime) : '--',
          style: TextStyle(
            color: c.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 28,
          height: 28,
          child: _refreshing
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  tooltip: l.tr('terminal.statusPanel.refresh'),
                  onPressed: widget.onRefresh == null ? null : _handleRefresh,
                  icon: Icon(Icons.refresh_rounded, color: c.muted),
                ),
        ),
      ],
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.label,
    required this.percentage,
    this.detail,
  });

  final String label;
  final double percentage;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _usageColor(c, percentage);
    final safePercentage = percentage.clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  label,
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
              ),
              Expanded(
                child: _buildProgressBar(c, color, safePercentage),
              ),
              const SizedBox(width: 8),
              if (detail != null)
                Text(
                  detail!,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(AppColorTheme c, Color color, double safePercentage) {
    return SizedBox(
      height: 18,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          FractionallySizedBox(
            widthFactor: safePercentage / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          Center(
            child: Text(
              '${safePercentage.toStringAsFixed(1)}%',
              style: TextStyle(
                color: c.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadAvgRow extends StatelessWidget {
  const _LoadAvgRow({
    required this.label,
    required this.loadAvg,
    required this.cpuCount,
  });

  final String label;
  final List<double> loadAvg;
  final int cpuCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effectiveCpuCount = cpuCount > 0 ? cpuCount : 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < loadAvg.length; i++) ...[
                  _buildLoadValue(c, loadAvg[i], effectiveCpuCount),
                  if (i < loadAvg.length - 1)
                    Text(
                      ', ',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadValue(AppColorTheme c, double load, int cores) {
    final isHigh = load >= cores;
    return Text(
      load.toStringAsFixed(2),
      style: TextStyle(
        color: isHigh ? c.danger : c.success,
        fontSize: 13,
        fontWeight: isHigh ? FontWeight.w700 : FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _DriveProgressRow extends StatelessWidget {
  const _DriveProgressRow({required this.drive, required this.label});

  final DriveInfo drive;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _usageColor(c, drive.usedPercentage);
    final safePercentage = drive.usedPercentage.clamp(0.0, 100.0);
    return Tooltip(
      message: '${drive.filesystem}  ${drive.mountedOn}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 18,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: safePercentage / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '${safePercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${drive.usedGb}/${drive.totalGb}G',
              style: TextStyle(
                color: c.muted,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  const _NetworkSection({required this.netstatInfo});

  final NetstatInfo netstatInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              AppLocalizations.of(context).tr('terminal.statusPanel.network'),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.arrow_upward_rounded, size: 14, color: const Color(0xFFCF8A20)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _speedFull(netstatInfo.outputMb),
                    style: const TextStyle(
                      color: Color(0xFFCF8A20),
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_downward_rounded, size: 14, color: const Color(0xFF67C23A)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _speedFull(netstatInfo.inputMb),
                    style: const TextStyle(
                      color: Color(0xFF67C23A),
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '--' : value,
              textAlign: TextAlign.right,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: c.muted),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onAction!(),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state});

  final ServerStatusMonitorState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ServerStatusMonitorState.idle => Theme.of(context).colorScheme.outline,
      ServerStatusMonitorState.connecting => Colors.amber,
      ServerStatusMonitorState.connected => Colors.green,
      ServerStatusMonitorState.error => context.colors.danger,
    };
    return Icon(Icons.circle, size: 8, color: color);
  }
}

String _stateText(AppLocalizations l, ServerStatusMonitorState state) {
  return switch (state) {
    ServerStatusMonitorState.idle => l.tr('terminal.statusPanel.idle'),
    ServerStatusMonitorState.connecting => l.tr(
      'terminal.statusPanel.connecting',
    ),
    ServerStatusMonitorState.connected => l.tr(
      'terminal.statusPanel.connected',
    ),
    ServerStatusMonitorState.error => l.tr('terminal.statusPanel.error'),
  };
}

Color _usageColor(AppColorTheme c, double value) {
  if (value < 60) return c.success;
  if (value < 80) return c.warning;
  return c.danger;
}

String _speedFull(double mb) {
  if (mb >= 1) return '${mb.toStringAsFixed(2)} MB/s';
  return '${(mb * 1024).toStringAsFixed(1)} KB/s';
}

String _gb(int mb) => (mb / 1024).toStringAsFixed(1);

String _formatDuration(double seconds) {
  final totalMinutes = (seconds / 60).floor();
  final days = totalMinutes ~/ 1440;
  final hours = (totalMinutes % 1440) ~/ 60;
  final minutes = totalMinutes % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
