import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../../core/api/api_result.dart';
import '../servers/server_model.dart';
import '../servers/server_repository.dart';
import 'terminal_session.dart';
import 'terminal_session_manager.dart';
import 'terminal_toolbar.dart';

class TerminalShellPage extends StatefulWidget {
  const TerminalShellPage({
    super.key,
    required this.manager,
    required this.repository,
    this.initialServers = const [],
    required this.onSessionExpired,
  });

  final TerminalSessionManager manager;
  final ServerRepository repository;
  final List<ServerModel> initialServers;
  final VoidCallback onSessionExpired;

  @override
  State<TerminalShellPage> createState() => _TerminalShellPageState();
}

class _TerminalShellPageState extends State<TerminalShellPage> {
  bool _openingServer = false;
  late List<ServerModel> _cachedServers;

  @override
  void initState() {
    super.initState();
    _cachedServers = widget.initialServers;
  }

  Future<void> _openServerMenu(BuildContext anchorContext) async {
    if (_openingServer) return;
    if (_cachedServers.isNotEmpty) {
      await _showServerMenu(anchorContext, _cachedServers);
      return;
    }

    setState(() => _openingServer = true);
    final List<ServerModel> servers;
    try {
      servers = await widget.repository.fetchHosts();
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        setState(() => _openingServer = false);
        widget.onSessionExpired();
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load servers: $error')));
      setState(() => _openingServer = false);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    setState(() => _openingServer = false);
    _cachedServers = servers;
    await _showServerMenu(anchorContext, servers);
  }

  Future<void> _showServerMenu(
    BuildContext anchorContext,
    List<ServerModel> servers,
  ) async {
    if (!mounted) return;
    final menuWidth = _menuWidthFor(context);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) return;

    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorTopLeft & anchorBox.size;
    final overlayRect = Offset.zero & overlayBox.size;
    final selected = await showMenu<ServerModel>(
      context: context,
      position: RelativeRect.fromRect(anchorRect, overlayRect),
      constraints: BoxConstraints.tightFor(width: menuWidth),
      items: servers.isEmpty
          ? const [
              PopupMenuItem<ServerModel>(
                enabled: false,
                child: Text('No servers available'),
              ),
            ]
          : [
              for (final server in servers.take(12))
                PopupMenuItem<ServerModel>(
                  enabled: server.canConnect,
                  value: server,
                  height: 56,
                  child: _OpenServerMenuItem(server: server),
                ),
            ],
    );
    if (selected == null || !mounted) return;
    try {
      final config = await widget.repository.fetchSshConfig(selected.id);
      await widget.manager.openSession(config);
    } catch (error) {
      if (!mounted) return;
      if (error is UnauthorizedFailure) {
        widget.onSessionExpired();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open terminal: $error')),
      );
    }
  }

  Future<void> _closeActive() async {
    final active = widget.manager.activeSession;
    if (active == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await widget.manager.closeSession(active.id);
    if (mounted && widget.manager.sessions.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) {
        final sessions = widget.manager.sessions.toList(growable: false);
        final active = widget.manager.activeSession;
        final activeIndex = active == null
            ? 0
            : math.max(
                0,
                sessions.indexWhere((session) => session.id == active.id),
              );
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                _TerminalTopBar(
                  sessions: sessions,
                  active: active,
                  openingServer: _openingServer,
                  onSelect: widget.manager.setActive,
                  onNew: _openServerMenu,
                  onClose: _closeActive,
                  onReconnect: active == null
                      ? null
                      : () => widget.manager.reconnect(active.id),
                ),
                Expanded(
                  child: ColoredBox(
                    color: Colors.black,
                    child: sessions.isEmpty
                        ? const Center(
                            child: Text(
                              'No active terminal',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : IndexedStack(
                            index: activeIndex,
                            children: [
                              for (final session in sessions)
                                TerminalView(session.controller.terminal),
                            ],
                          ),
                  ),
                ),
                TerminalToolbar(
                  onInput: (value) => widget.manager.activeSession?.controller
                      .writeInput(value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TerminalTopBar extends StatelessWidget {
  const _TerminalTopBar({
    required this.sessions,
    required this.active,
    required this.openingServer,
    required this.onSelect,
    required this.onNew,
    required this.onClose,
    required this.onReconnect,
  });

  final List<TerminalSession> sessions;
  final TerminalSession? active;
  final bool openingServer;
  final ValueChanged<String> onSelect;
  final ValueChanged<BuildContext> onNew;
  final VoidCallback onClose;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final activeSession = active;
    final menuWidth = _menuWidthFor(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Sessions',
            constraints: BoxConstraints.tightFor(width: menuWidth),
            onSelected: onSelect,
            itemBuilder: (context) => [
              for (final session in sessions)
                PopupMenuItem(
                  value: session.id,
                  child: Row(
                    children: [
                      _StatusDot(status: session.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          session.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.id == activeSession?.id)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
            child: SizedBox(
              width: 42,
              height: 42,
              child: CustomPaint(
                painter: _StackedSessionsPainter(count: sessions.length),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: activeSession == null
                ? const Text('Terminal', overflow: TextOverflow.ellipsis)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeSession.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Row(
                        children: [
                          _StatusDot(status: activeSession.status),
                          const SizedBox(width: 6),
                          Text(
                            _statusText(activeSession.status),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          IconButton(
            tooltip: 'Reconnect',
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close terminal',
            onPressed: activeSession == null ? null : onClose,
            icon: const Icon(Icons.close),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'New terminal',
              onPressed: openingServer ? null : () => onNew(buttonContext),
              icon: openingServer
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenServerMenuItem extends StatelessWidget {
  const _OpenServerMenuItem({required this.server});

  final ServerModel server;

  @override
  Widget build(BuildContext context) {
    final title = server.name.isEmpty ? server.host : server.name;
    final detail = '${server.username}@${server.host}:${server.port}';
    final textColor = server.canConnect
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).disabledColor;
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: server.canConnect
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
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

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final TerminalSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TerminalSessionStatus.connecting => Colors.amber,
      TerminalSessionStatus.connected => Colors.green,
      TerminalSessionStatus.disconnected => Colors.grey,
      TerminalSessionStatus.error => Theme.of(context).colorScheme.error,
    };
    return Icon(Icons.circle, size: 9, color: color);
  }
}

class _StackedSessionsPainter extends CustomPainter {
  const _StackedSessionsPainter({required this.count});
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final visibleLayers = count <= 0 ? 1 : math.min(count, 3);
    final layerColors = [
      const Color(0xff0f766e),
      const Color(0xff4f46e5),
      const Color(0xff22d3ee),
    ];
    final strokeColors = [
      const Color(0xff99f6e4),
      const Color(0xffc4b5fd),
      const Color(0xffecfeff),
    ];
    final offsets = [
      const Offset(3, 13),
      const Offset(8, 8),
      const Offset(13, 3),
    ];

    for (var i = 0; i < visibleLayers; i++) {
      final layerIndex = visibleLayers == 1 ? 2 : i;
      final rect = offsets[i] & Size(size.width - 18, size.height - 18);
      final radius = Radius.circular(i == visibleLayers - 1 ? 6 : 5);
      final rrect = RRect.fromRectAndRadius(rect, radius);
      final path = Path()..addRRect(rrect);

      canvas.drawShadow(
        path,
        Colors.black.withValues(alpha: 0.28),
        3 + i.toDouble(),
        false,
      );

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(layerColors[layerIndex], Colors.white, 0.16)!,
            layerColors[layerIndex],
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, fill);

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == visibleLayers - 1 ? 1.4 : 1
        ..color = strokeColors[layerIndex].withValues(alpha: 0.72);
      canvas.drawRRect(rrect.deflate(0.5), stroke);

      final highlight = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(
          alpha: i == visibleLayers - 1 ? 0.42 : 0.22,
        );
      canvas.drawLine(
        rect.topLeft + const Offset(5, 5),
        rect.topRight + const Offset(-5, 5),
        highlight,
      );
    }

    if (count > 1) {
      final badgeCenter = Offset(size.width - 8, 9);
      final badgeShadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(badgeCenter + const Offset(0, 1), 10, badgeShadow);

      final badgeFill = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfffff7ed), Color(0xfff59e0b)],
        ).createShader(Rect.fromCircle(center: badgeCenter, radius: 9));
      canvas.drawCircle(badgeCenter, 9, badgeFill);

      final badgeStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xffffffff);
      canvas.drawCircle(badgeCenter, 9, badgeStroke);

      final textPainter = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : count.toString(),
          style: const TextStyle(
            color: Color(0xff451a03),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - textPainter.width / 2,
          badgeCenter.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StackedSessionsPainter oldDelegate) {
    return oldDelegate.count != count;
  }
}

String _statusText(TerminalSessionStatus status) {
  return switch (status) {
    TerminalSessionStatus.connecting => 'Connecting',
    TerminalSessionStatus.connected => 'Connected',
    TerminalSessionStatus.disconnected => 'Disconnected',
    TerminalSessionStatus.error => 'Error',
  };
}

double _menuWidthFor(BuildContext context) {
  return MediaQuery.sizeOf(context).width / 2;
}
