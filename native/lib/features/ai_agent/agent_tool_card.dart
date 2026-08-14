part of 'agent_panel.dart';

class AgentToolCard extends StatefulWidget {
  const AgentToolCard({super.key, required this.part});
  final AgentToolPart part;

  @override
  State<AgentToolCard> createState() => _AgentToolCardState();
}

class _AgentToolCardState extends State<AgentToolCard> {
  late bool expanded =
      widget.part.status == AgentToolStatus.error ||
      widget.part.status == AgentToolStatus.denied;

  @override
  void didUpdateWidget(AgentToolCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameFailure =
        oldWidget.part.status != widget.part.status &&
        (widget.part.status == AgentToolStatus.error ||
            widget.part.status == AgentToolStatus.denied);
    if (becameFailure) expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final l = AppLocalizations.of(context);
    final tone = _toolTone(context, part.status);
    final radius = BorderRadius.circular(AgentUiTokens.radiusMedium);
    final hasDetails =
        part.input.isNotEmpty ||
        part.risk?['reason'] != null ||
        part.error != null ||
        part.output != null;
    final summary = _toolSummary(part);
    return AnimatedContainer(
      key: ValueKey('agent-tool-${part.toolCallId}'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: expanded
            ? Color.alphaBlend(
                tone.foreground.withValues(alpha: 0.035),
                context.colors.card,
              )
            : context.colors.card,
        border: Border.all(color: tone.border, width: 1),
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: hasDetails,
            expanded: hasDetails ? expanded : null,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('agent-tool-toggle-${part.toolCallId}'),
                borderRadius: radius,
                onTap: hasDetails
                    ? () => setState(() => expanded = !expanded)
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AgentUiTokens.messagePartHeaderMinHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tone.background,
                            borderRadius: BorderRadius.circular(
                              AgentUiTokens.radiusSmall,
                            ),
                          ),
                          child: part.status == AgentToolStatus.running
                              ? SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tone.foreground,
                                  ),
                                )
                              : Icon(
                                  _toolStatusIcon(part.status),
                                  size: 17,
                                  color: tone.foreground,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _toolLabel(l, part.tool),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tone.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _toolStatusLabel(l, part.status),
                            style: TextStyle(
                              color: tone.foreground,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasDetails) ...[
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded && hasDetails
                ? Padding(
                    key: ValueKey('agent-tool-details-${part.toolCallId}'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (part.risk?['reason'] != null)
                          _DetailBlock(
                            label:
                                part.risk?['category']?.toString() ??
                                l.tr('agent.risk'),
                            text: part.risk!['reason'].toString(),
                            danger: true,
                          ),
                        if (part.input.isNotEmpty)
                          _DetailBlock(
                            label: l.tr('agent.arguments'),
                            text: const JsonEncoder.withIndent(
                              '  ',
                            ).convert(part.input),
                          ),
                        if (part.error != null)
                          _DetailBlock(
                            label: l.tr('common.error'),
                            text: part.error == 'tool_incomplete'
                                ? l.tr('agent.toolIncomplete')
                                : part.error!,
                            danger: true,
                          )
                        else if (part.output != null)
                          _DetailBlock(
                            label: l.tr('agent.result'),
                            text: _stringifyOutput(part.output),
                            copyable: true,
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.text,
    this.danger = false,
    this.copyable = false,
  });
  final String label;
  final String text;
  final bool danger;
  final bool copyable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: danger ? context.colors.danger : context.colors.muted,
                ),
              ),
            ),
            if (copyable)
              IconButton(
                tooltip: AppLocalizations.of(context).tr('common.copy'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                icon: const Icon(Icons.copy_outlined, size: 16),
              ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.colors.chip,
            borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
            border: Border.all(
              color: danger
                  ? context.colors.dangerBorder
                  : context.colors.border,
            ),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: danger ? context.colors.danger : context.colors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

IconData _toolStatusIcon(AgentToolStatus status) => switch (status) {
  AgentToolStatus.running => Icons.sync,
  AgentToolStatus.awaitingApproval => Icons.schedule_rounded,
  AgentToolStatus.done => Icons.check_rounded,
  AgentToolStatus.error => Icons.priority_high_rounded,
  AgentToolStatus.denied => Icons.block_rounded,
};

String _toolStatusLabel(AppLocalizations l, AgentToolStatus status) =>
    switch (status) {
      AgentToolStatus.running => l.tr('agent.toolStatus.running'),
      AgentToolStatus.awaitingApproval => l.tr(
        'agent.toolStatus.awaitingApproval',
      ),
      AgentToolStatus.done => l.tr('agent.toolStatus.done'),
      AgentToolStatus.error => l.tr('agent.toolStatus.error'),
      AgentToolStatus.denied => l.tr('agent.toolStatus.denied'),
    };

({Color foreground, Color background, Color border}) _toolTone(
  BuildContext context,
  AgentToolStatus status,
) {
  final colors = context.colors;
  final foreground = switch (status) {
    AgentToolStatus.running => colors.primary,
    AgentToolStatus.awaitingApproval => colors.warning,
    AgentToolStatus.done => colors.success,
    AgentToolStatus.error || AgentToolStatus.denied => colors.danger,
  };
  return (
    foreground: foreground,
    background: foreground.withValues(alpha: 0.11),
    border: foreground.withValues(alpha: 0.28),
  );
}

String _toolLabel(AppLocalizations l, String tool) {
  final key = 'agent.tool.$tool';
  final label = l.tr(key);
  return label == key ? tool : label;
}

String _toolSummary(AgentToolPart part) {
  final input = part.input;
  return (input['scriptName'] ??
          input['command'] ??
          input['path'] ??
          input['keyword'] ??
          '')
      .toString();
}

String _stringifyOutput(Object? output) {
  if (output == null) return '';
  if (output is String) return output;
  if (output is Map &&
      (output.containsKey('stdout') || output.containsKey('stderr'))) {
    final lines = <String>[];
    if (output['stdout']?.toString().isNotEmpty == true) {
      lines.add(output['stdout'].toString());
    }
    if (output['stderr']?.toString().isNotEmpty == true) {
      lines.add('[stderr]\n${output['stderr']}');
    }
    if (output['exitCode'] != null && output['exitCode'] != 0) {
      lines.add('[exit] ${output['exitCode']}');
    }
    return lines.join('\n\n');
  }
  return const JsonEncoder.withIndent('  ').convert(output);
}
