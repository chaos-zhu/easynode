import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/agent_providers.dart';
import '../../state/storage_providers.dart';
import 'agent_panel.dart';
import 'agent_ui_tokens.dart';

class AgentNavigationObserver extends NavigatorObserver {
  final ValueNotifier<bool> modalRouteActive = ValueNotifier(false);

  void _update(Route<dynamic>? route) {
    modalRouteActive.value = route is PopupRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
  }

  void dispose() => modalRouteActive.dispose();
}

class AgentGlobalOverlay extends ConsumerStatefulWidget {
  const AgentGlobalOverlay({
    super.key,
    required this.navigationObserver,
    required this.navigatorKey,
    this.compactPageBuilder,
  });

  final AgentNavigationObserver navigationObserver;
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder? compactPageBuilder;

  @override
  ConsumerState<AgentGlobalOverlay> createState() => _AgentGlobalOverlayState();
}

class _AgentGlobalOverlayState extends ConsumerState<AgentGlobalOverlay> {
  bool _panelOpen = false;
  late String _side;
  late double _yFraction;
  double? _dragX;
  double? _dragY;
  double _lastX = 0;
  double _lastY = 0;
  bool _entryFocused = false;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(appStorageProvider);
    _side = storage.agentEntrySide;
    _yFraction = storage.agentEntryY;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(nativeAgentEnabledProvider);
    if (enabled) {
      // Keeping this provider watched here lets an active turn continue while
      // its panel is closed. It is disposed with the authenticated overlay.
      ref.watch(agentKeepAliveProvider);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: widget.navigationObserver.modalRouteActive,
      builder: (context, modalActive, _) {
        if (!enabled || _panelOpen || modalActive) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              const size = AgentUiTokens.entrySize;
              final topInset = media.padding.top + AgentUiTokens.edgeGap;
              final bottomInset = media.viewInsets.bottom > 0
                  ? media.viewInsets.bottom + AgentUiTokens.edgeGap
                  : media.padding.bottom + 84;
              const minX = AgentUiTokens.entryHorizontalInset;
              final maxX =
                  (constraints.maxWidth -
                          size -
                          AgentUiTokens.entryHorizontalInset)
                      .clamp(minX, double.infinity)
                      .toDouble();
              final maxY = (constraints.maxHeight - size - bottomInset)
                  .clamp(topInset, double.infinity)
                  .toDouble();
              final range = (maxY - topInset)
                  .clamp(1.0, double.infinity)
                  .toDouble();
              _lastX = (_dragX ?? (_side == 'left' ? minX : maxX))
                  .clamp(minX, maxX)
                  .toDouble();
              _lastY = (_dragY ?? topInset + range * _yFraction)
                  .clamp(topInset, maxY)
                  .toDouble();
              return Stack(
                children: [
                  AnimatedPositioned(
                    left: _lastX,
                    top: _lastY,
                    width: size,
                    height: size,
                    duration: _dragX == null
                        ? AgentUiTokens.entrySnapDuration
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    child: FocusableActionDetector(
                      onShowFocusHighlight: (value) {
                        if (mounted) setState(() => _entryFocused = value);
                      },
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            ActivateIntent(),
                        SingleActivator(LogicalKeyboardKey.space):
                            ActivateIntent(),
                        SingleActivator(
                          LogicalKeyboardKey.keyA,
                          control: true,
                          shift: true,
                        ): ActivateIntent(),
                      },
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            _openPanel();
                            return null;
                          },
                        ),
                      },
                      child: Semantics(
                        key: const Key('agent-global-entry'),
                        button: true,
                        label: AppLocalizations.of(context).tr('agent.open'),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) {
                            _dragX = _lastX;
                            _dragY = _lastY;
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _dragX = (_dragX! + details.delta.dx)
                                  .clamp(minX, maxX)
                                  .toDouble();
                              _dragY = (_dragY! + details.delta.dy)
                                  .clamp(topInset, maxY)
                                  .toDouble();
                            });
                          },
                          onPanEnd: (_) async {
                            final nextSide =
                                _dragX! + size / 2 < constraints.maxWidth / 2
                                ? 'left'
                                : 'right';
                            final nextFraction = ((_dragY! - topInset) / range)
                                .clamp(0.0, 1.0)
                                .toDouble();
                            setState(() {
                              _side = nextSide;
                              _yFraction = nextFraction;
                              _dragX = null;
                              _dragY = null;
                            });
                            final storage = ref.read(appStorageProvider);
                            await Future.wait([
                              storage.setAgentEntrySide(nextSide),
                              storage.setAgentEntryY(nextFraction),
                            ]);
                          },
                          child: Material(
                            color: context.colors.card,
                            elevation: 8,
                            shape: CircleBorder(
                              side: BorderSide(
                                color: _entryFocused
                                    ? context.colors.primary
                                    : context.colors.border,
                                width: _entryFocused ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _openPanel,
                              customBorder: const CircleBorder(),
                              child: CustomPaint(
                                painter: _RobotAvatarPainter(
                                  primary: context.colors.primary,
                                  accent: context.colors.accent,
                                  face: context.colors.card,
                                  line: context.colors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openPanel() async {
    if (_panelOpen) return;
    setState(() => _panelOpen = true);
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      if (mounted) setState(() => _panelOpen = false);
      return;
    }
    try {
      if (MediaQuery.sizeOf(context).width < AgentUiTokens.compactBreakpoint) {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: widget.compactPageBuilder ?? (_) => const AgentPage(),
          ),
        );
      } else {
        final overlayContext = navigator.overlay?.context;
        if (overlayContext == null) return;
        await showGeneralDialog<void>(
          context: overlayContext,
          useRootNavigator: false,
          barrierDismissible: false,
          barrierColor: Theme.of(
            context,
          ).colorScheme.scrim.withValues(alpha: 0.18),
          transitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (_, _, _) => const AgentWideDialog(),
          transitionBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(animation),
              child: child,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _panelOpen = false);
    }
  }
}

class _RobotAvatarPainter extends CustomPainter {
  const _RobotAvatarPainter({
    required this.primary,
    required this.accent,
    required this.face,
    required this.line,
  });

  final Color primary;
  final Color accent;
  final Color face;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 56;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(10 * scale, 13 * scale, 36 * scale, 32 * scale),
      Radius.circular(11 * scale),
    );
    canvas.drawRRect(body, Paint()..color = primary);
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(15 * scale, 19 * scale, 26 * scale, 18 * scale),
      Radius.circular(7 * scale),
    );
    canvas.drawRRect(screen, Paint()..color = face);
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 2.1 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(21 * scale, 27 * scale),
      Offset(23 * scale, 29 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(23 * scale, 29 * scale),
      Offset(21 * scale, 31 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(31 * scale, 31 * scale),
      Offset(36 * scale, 31 * scale),
      stroke,
    );
    canvas.drawCircle(
      Offset(42 * scale, 15 * scale),
      4 * scale,
      Paint()..color = accent,
    );
    canvas.drawLine(
      Offset(28 * scale, 13 * scale),
      Offset(28 * scale, 8 * scale),
      stroke,
    );
    canvas.drawCircle(
      Offset(28 * scale, 7 * scale),
      2.5 * scale,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RobotAvatarPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.accent != accent ||
      oldDelegate.face != face ||
      oldDelegate.line != line;
}
