part of 'agent_panel.dart';

class AgentPage extends StatelessWidget {
  const AgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: const SafeArea(child: AgentPanel()),
    );
  }
}

class AgentWideDialog extends StatefulWidget {
  const AgentWideDialog({super.key, this.panelBuilder});

  final WidgetBuilder? panelBuilder;

  @override
  State<AgentWideDialog> createState() => _AgentWideDialogState();
}

class _AgentWideDialogState extends State<AgentWideDialog> {
  Offset? _position;
  Size _size = const Size(AgentUiTokens.wideWidth, AgentUiTokens.wideHeight);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewport = Size(
      media.size.width,
      math.max(280, media.size.height - media.viewInsets.bottom),
    );
    final availableWidth = math.max(280.0, viewport.width - 24);
    final availableHeight = math.max(240.0, viewport.height - 24);
    _size = Size(
      _size.width
          .clamp(
            math.min(AgentUiTokens.wideMinWidth, availableWidth),
            availableWidth,
          )
          .toDouble(),
      _size.height
          .clamp(
            math.min(AgentUiTokens.wideMinHeight, availableHeight),
            availableHeight,
          )
          .toDouble(),
    );
    final position =
        _position ??
        Offset(
          viewport.width - _size.width - 24,
          (viewport.height - _size.height).clamp(12.0, 32.0),
        );
    _position = _clampPosition(position, viewport, _size);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: _position!.dx,
            top: _position!.dy,
            width: _size.width,
            height: _size.height,
            child: Material(
              key: const Key('agent-wide-window'),
              color: context.colors.card,
              elevation: 18,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusLarge),
                side: BorderSide(color: context.colors.border),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          setState(() {
                            _position = _clampPosition(
                              _position! + details.delta,
                              viewport,
                              _size,
                            );
                          });
                        },
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            color: context.colors.card,
                            border: Border(
                              bottom: BorderSide(color: context.colors.border),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: context.colors.strongBorder,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                            widget.panelBuilder?.call(context) ??
                            const AgentPanel(),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        setState(() {
                          _size = Size(
                            (_size.width + details.delta.dx)
                                .clamp(
                                  math.min(
                                    AgentUiTokens.wideMinWidth,
                                    viewport.width - _position!.dx - 12,
                                  ),
                                  viewport.width - _position!.dx - 12,
                                )
                                .toDouble(),
                            (_size.height + details.delta.dy)
                                .clamp(
                                  math.min(
                                    AgentUiTokens.wideMinHeight,
                                    viewport.height - _position!.dy - 12,
                                  ),
                                  viewport.height - _position!.dy - 12,
                                )
                                .toDouble(),
                          );
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle,
                          size: 18,
                          color: context.colors.softMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset _clampPosition(Offset value, Size viewport, Size window) => Offset(
    value.dx
        .clamp(
          12.0,
          (viewport.width - window.width - 12).clamp(12.0, double.infinity),
        )
        .toDouble(),
    value.dy
        .clamp(
          12.0,
          (viewport.height - window.height - 12).clamp(12.0, double.infinity),
        )
        .toDouble(),
  );
}
