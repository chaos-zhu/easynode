import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/app_color_theme.dart';
import '../server_status_monitor_manager.dart';
import 'desktop_terminal_workspace.dart';
import 'terminal_widgets.dart';

class DesktopTerminalStatusPanel extends StatefulWidget {
  const DesktopTerminalStatusPanel({
    super.key,
    required this.pane,
    required this.monitor,
  });
  final DesktopTerminalPane pane;
  final ServerStatusMonitorManager monitor;
  @override
  State<DesktopTerminalStatusPanel> createState() =>
      _DesktopTerminalStatusPanelState();
}

class _DesktopTerminalStatusPanelState
    extends State<DesktopTerminalStatusPanel> {
  final List<double> _incoming = [], _outgoing = [];
  DateTime? _lastUpdate;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.monitor,
    builder: (context, _) {
      final pane = widget.pane;
      final entry = widget.monitor.entryForHost(pane.server.id);
      final snapshot = entry?.snapshot;
      if (snapshot != null && snapshot.updatedAt != _lastUpdate) {
        _lastUpdate = snapshot.updatedAt;
        _incoming.add(snapshot.netstatInfo.inputMb);
        _outgoing.add(snapshot.netstatInfo.outputMb);
        if (_incoming.length > 60) {
          _incoming.removeAt(0);
          _outgoing.removeAt(0);
        }
      }
      Widget row(String title, Widget child) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.border, width: .5),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 48,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: context.colors.chip,
                  border: Border(
                    right: BorderSide(color: context.colors.border, width: .5),
                  ),
                ),
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: context.colors.muted),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 7,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      );
      Widget text(String value, {Color? color}) => SelectableText(
        value,
        style: TextStyle(fontSize: 12, color: color ?? context.colors.text),
      );
      Widget hostAction(IconData icon, String label, VoidCallback? action) =>
          SizedBox(
            width: 22,
            height: 20,
            child: IconButton(
              onPressed: action,
              icon: TerminalIcon(icon, size: 13),
              tooltip: label,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          );
      final latency = pane.latency?.inMilliseconds;
      final latencyColor = latency == null
          ? context.colors.muted
          : latency < 100
          ? context.colors.success
          : latency < 250
          ? context.colors.warning
          : context.colors.danger;
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          row(
            dt(context, 'hostLabel'),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: pane.server.host,
                    child: Text(
                      pane.server.host,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: dt(context, 'localLatency'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: latencyColor.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      latency == null ? '—' : '${latency}ms',
                      style: TextStyle(fontSize: 10, color: latencyColor),
                    ),
                  ),
                ),
                hostAction(
                  Icons.copy_outlined,
                  dt(context, 'copy'),
                  () =>
                      Clipboard.setData(ClipboardData(text: pane.server.host)),
                ),
                hostAction(
                  Icons.refresh,
                  dt(context, 'reconnectMonitor'),
                  pane.config == null
                      ? null
                      : () => widget.monitor.startNow(pane.config!),
                ),
              ],
            ),
          ),
          if (snapshot == null) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(10),
              child: text(entry?.lastError ?? dt(context, 'waitingStatus')),
            ),
            if (entry?.state == ServerStatusMonitorState.error)
              TextButton(
                onPressed: pane.config == null
                    ? null
                    : () => widget.monitor.startNow(pane.config!),
                child: Text(dt(context, 'retry')),
              ),
          ] else ...[
            row(
              dt(context, 'uptime'),
              text(
                '${(snapshot.osInfo.uptime / 86400).floor()}d ${(snapshot.osInfo.uptime / 3600).floor() % 24}h ${(snapshot.osInfo.uptime / 60).floor() % 60}m',
              ),
            ),
            const SizedBox(height: 15),
            row('CPU', _Percent(value: snapshot.cpuInfo.cpuUsage)),
            row(
              dt(context, 'load'),
              text(
                snapshot.cpuInfo.loadAvg
                    .map((v) => v.toStringAsFixed(2))
                    .join(', '),
                color: context.colors.success,
              ),
            ),
            row(
              dt(context, 'memory'),
              _Percent(
                value: snapshot.memInfo.usedMemPercentage,
                detail: _memoryPair(
                  snapshot.memInfo.usedMemMb.toDouble(),
                  snapshot.memInfo.totalMemMb.toDouble(),
                ),
              ),
            ),
            row(
              dt(context, 'swap'),
              _Percent(
                value: snapshot.swapInfo.swapPercentage,
                detail: _memoryPair(
                  snapshot.swapInfo.swapUsed.toDouble(),
                  snapshot.swapInfo.swapTotal.toDouble(),
                ),
              ),
            ),
            for (final drive in snapshot.drivesInfo)
              row(
                dt(context, 'disk'),
                Tooltip(
                  message: '${drive.mountedOn} · ${drive.filesystem}',
                  child: _Percent(
                    value: drive.usedPercentage,
                    detail:
                        '${drive.usedGb.toStringAsFixed(1)}/${drive.totalGb.toStringAsFixed(1)}G',
                  ),
                ),
              ),
            row(
              dt(context, 'network'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tooltip(
                    message: snapshot.netstatInfo.interfaceName ?? '',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '↑ ${_rate(snapshot.netstatInfo.outputMb)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.warning,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '↓ ${_rate(snapshot.netstatInfo.inputMb)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: CustomPaint(
                      painter: TerminalSparkline(
                        [_incoming, _outgoing],
                        [context.colors.success, context.colors.warning],
                        gridColor: context.colors.border,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            row(dt(context, 'hostname'), text(snapshot.osInfo.hostname)),
            row(dt(context, 'cores'), text('${snapshot.cpuInfo.cpuCount}')),
            row(dt(context, 'cpuModel'), text(snapshot.cpuInfo.cpuModel)),
            row(
              dt(context, 'system'),
              text(
                '${snapshot.osInfo.type} ${snapshot.osInfo.release}\n${snapshot.osInfo.arch}',
              ),
            ),
          ],
        ],
      );
    },
  );

  static String _memoryPair(double used, double total) => total >= 1024
      ? '${(used / 1024).toStringAsFixed(1)}/${(total / 1024).toStringAsFixed(1)}G'
      : '${used.toStringAsFixed(0)}/${total.toStringAsFixed(0)}M';
  static String _rate(double mb) => mb >= 1
      ? '${mb.toStringAsFixed(1)} MB/s'
      : '${(mb * 1024).toStringAsFixed(1)} KB/s';
}

class _Percent extends StatelessWidget {
  const _Percent({required this.value, this.detail});
  final double value;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final color = value >= 80
        ? context.colors.danger
        : value >= 60
        ? context.colors.warning
        : context.colors.success;
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value.clamp(0, 100) / 100,
            minHeight: 18,
            color: color,
            backgroundColor: context.colors.text.withValues(alpha: .12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              Text(
                '${value.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 11, color: context.colors.text),
              ),
              if (detail != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    detail!,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.colors.text),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DesktopTerminalStatusBar extends StatelessWidget {
  const DesktopTerminalStatusBar({
    super.key,
    required this.pane,
    required this.monitor,
  });
  final DesktopTerminalPane pane;
  final ServerStatusMonitorManager monitor;

  Color _level(
    BuildContext context,
    num? value, {
    int warning = 60,
    int danger = 80,
  }) => value == null
      ? context.colors.softMuted
      : value >= danger
      ? context.colors.danger
      : value >= warning
      ? context.colors.warning
      : context.colors.success;

  String _rate(double? mb) => mb == null
      ? '—'
      : mb >= 1
      ? '${mb.toStringAsFixed(2)} MB/s'
      : '${(mb * 1024).toStringAsFixed(1)} KB/s';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: monitor,
    builder: (context, _) {
      final entry = monitor.entryForHost(pane.server.id);
      final connected = entry?.state == ServerStatusMonitorState.connected;
      final snapshot = connected ? entry?.snapshot : null;
      final latency = pane.latency?.inMilliseconds;
      final cpu = snapshot?.cpuInfo.cpuUsage;
      final memory = snapshot?.memInfo.usedMemPercentage;
      final color = switch (entry?.state) {
        ServerStatusMonitorState.connected => context.colors.success,
        ServerStatusMonitorState.connecting => context.colors.warning,
        ServerStatusMonitorState.error => context.colors.danger,
        _ => context.colors.softMuted,
      };
      Widget separator() =>
          Container(width: 1, height: 14, color: context.colors.border);
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: context.colors.chip,
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 28,
                child: IconButton(
                  tooltip:
                      '${pane.server.host}\n${entry?.lastError ?? dt(context, 'reconnectMonitor')}',
                  onPressed: pane.config == null
                      ? null
                      : () => monitor.startNow(pane.config!),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              _StatusMetric(
                tooltip: dt(context, 'localLatency'),
                icon: Icons.link,
                value: '${latency ?? '—'} ms',
                color: _level(context, latency, warning: 100, danger: 250),
                trailing: Text(
                  'RTT',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1,
                    color: context.colors.softMuted,
                  ),
                ),
              ),
              separator(),
              _StatusMetric(
                tooltip: 'CPU',
                icon: Icons.memory,
                value: cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%',
                color: _level(context, cpu),
              ),
              separator(),
              _StatusMetric(
                tooltip: snapshot == null
                    ? dt(context, 'memory')
                    : '${dt(context, 'memory')} ${snapshot.memInfo.usedMemMb} / ${snapshot.memInfo.totalMemMb} MB',
                icon: Icons.developer_board_outlined,
                value: memory == null ? '—' : '${memory.toStringAsFixed(1)}%',
                color: _level(context, memory),
              ),
              separator(),
              _StatusMetric(
                tooltip: dt(context, 'network'),
                icon: Icons.upload,
                iconColor: context.colors.warning,
                value: _rate(snapshot?.netstatInfo.outputMb),
                color: context.colors.muted,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TerminalIcon(
                      Icons.download,
                      size: 13,
                      color: context.colors.success,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _rate(snapshot?.netstatInfo.inputMb),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _StatusMetric extends StatefulWidget {
  const _StatusMetric({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.color,
    this.iconColor,
    this.trailing,
  });
  final String tooltip, value;
  final IconData icon;
  final Color color;
  final Color? iconColor;
  final Widget? trailing;
  @override
  State<_StatusMetric> createState() => _StatusMetricState();
}

class _StatusMetricState extends State<_StatusMetric> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    waitDuration: const Duration(milliseconds: 300),
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 23,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hovered
              ? context.colors.border.withValues(alpha: .3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TerminalIcon(
              widget.icon,
              size: 13,
              color: widget.iconColor ?? widget.color,
            ),
            const SizedBox(width: 4),
            Text(
              widget.value,
              style: TextStyle(fontSize: 11, height: 1, color: widget.color),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 4),
              widget.trailing!,
            ],
          ],
        ),
      ),
    ),
  );
}

class TerminalSparkline extends CustomPainter {
  TerminalSparkline(this.series, this.colors, {this.gridColor});
  final Color? gridColor;
  final List<List<double>> series;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = math.max(
      .001,
      series.expand((s) => s).fold<double>(0, math.max),
    );
    if (gridColor != null) {
      final paint = Paint()
        ..color = gridColor!.withValues(alpha: .5)
        ..strokeWidth = .5;
      for (var i = 0; i < 3; i++) {
        final y = 5 + (size.height - 10) * i / 2;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    for (var i = 0; i < series.length; i++) {
      final data = series[i];
      if (data.length < 2) continue;
      final path = Path();
      for (var j = 0; j < data.length; j++) {
        final x = size.width * j / (data.length - 1),
            y = size.height - data[j] / maxValue * (size.height - 8);
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(TerminalSparkline oldDelegate) => true;
}
