part of 'agent_panel.dart';

class AgentApprovalCard extends ConsumerStatefulWidget {
  const AgentApprovalCard({
    super.key,
    required this.approval,
    this.docked = false,
  });
  final AgentApproval approval;
  final bool docked;

  @override
  ConsumerState<AgentApprovalCard> createState() => _AgentApprovalCardState();
}

class _AgentApprovalCardState extends ConsumerState<AgentApprovalCard> {
  Timer? timer;
  var now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.approval;
    final remaining = ((5 * 60 * 1000 - (now - item.createdAt)) / 1000)
        .ceil()
        .clamp(0, 300);
    final l = AppLocalizations.of(context);
    final preview = item.preview;
    final allowButton = FilledButton(
      onPressed: () => ref
          .read(agentControllerProvider.notifier)
          .approve(item.requestId, true),
      child: Text(l.tr('agent.approval.allow')),
    );
    final denyButton = TextButton(
      onPressed: () => ref
          .read(agentControllerProvider.notifier)
          .approve(item.requestId, false),
      child: Text(
        l.tr('agent.approval.deny'),
        style: TextStyle(color: context.colors.danger),
      ),
    );
    final sessionButton = item.grantable
        ? OutlinedButton(
            onPressed: () => ref
                .read(agentControllerProvider.notifier)
                .approve(item.requestId, true, scope: 'session'),
            child: Text(
              item.isMcp
                  ? l.tr('agent.approval.allowMcpSession')
                  : l.tr('agent.approval.allowSession'),
            ),
          )
        : null;
    final actions = widget.docked
        ? [allowButton, denyButton, ?sessionButton]
        : [allowButton, ?sessionButton, denyButton];
    final details = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.docked
            ? 128
            : AgentUiTokens.messagePartContentMaxHeight,
      ),
      child: SingleChildScrollView(
        key: const Key('agent-approval-details-scroll'),
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.isMcp
                  ? l.trf('agent.approval.providerDescription', [
                      item.providerName ??
                          item.toolInfo?['providerName']?.toString() ??
                          'MCP',
                      item.displayName,
                    ])
                  : l.trf('agent.approval.description', [
                      item.hostName ?? '-',
                      _toolLabel(l, item.tool),
                    ]),
            ),
            if (item.effect != null) ...[
              SizedBox(height: widget.docked ? 4 : 6),
              Text(
                l.trf('agent.approval.scope', [
                  l.tr('agent.effect.${item.effect}'),
                ]),
                style: TextStyle(color: context.colors.muted),
              ),
            ],
            if (item.targets.isNotEmpty)
              _DetailBlock(
                label: l.tr('agent.approval.targets'),
                text: item.targets.join('\n'),
              ),
            if (item.sensitiveDisclosure) ...[
              SizedBox(height: widget.docked ? 6 : 8),
              Text(
                l.tr('agent.approval.sensitive'),
                style: TextStyle(
                  color: context.colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (preview?['diff'] != null)
              _DetailBlock(
                label: l.tr('agent.approval.diff'),
                text: preview!['diff'].toString(),
                copyable: true,
              )
            else
              _DetailBlock(
                label: l.tr('agent.arguments'),
                text: const JsonEncoder.withIndent('  ').convert(item.input),
              ),
            if (item.risk?['reason'] != null)
              Padding(
                padding: EdgeInsets.only(top: widget.docked ? 6 : 8),
                child: Text(
                  item.risk!['reason'].toString(),
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
          ],
        ),
      ),
    );
    return Container(
      margin: widget.docked
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(widget.docked ? 10 : 14),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.09),
        border: Border.all(color: context.colors.warning),
        borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: context.colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.tr('agent.approval.title'),
                  maxLines: widget.docked ? 1 : null,
                  overflow: widget.docked ? TextOverflow.ellipsis : null,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
              ),
            ],
          ),
          SizedBox(height: widget.docked ? 6 : 10),
          if (widget.docked) Flexible(child: details) else details,
          SizedBox(height: widget.docked ? 8 : 12),
          if (widget.docked)
            SingleChildScrollView(
              key: const Key('agent-approval-actions-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    actions[index],
                  ],
                ],
              ),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class AgentApprovalDock extends StatelessWidget {
  const AgentApprovalDock({
    super.key,
    required this.approvals,
    required this.maxHeight,
  });

  final List<AgentApproval> approvals;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      key: const Key('agent-approval-dock'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (approvals.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
              child: Text(
                l.trf('agent.approval.queueRemaining', [approvals.length - 1]),
                key: const Key('agent-approval-queue-count'),
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            ),
          Flexible(
            child: AgentApprovalCard(
              key: ValueKey('agent-approval-${approvals.first.requestId}'),
              approval: approvals.first,
              docked: true,
            ),
          ),
        ],
      ),
    );
  }
}
