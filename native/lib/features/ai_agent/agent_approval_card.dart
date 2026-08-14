part of 'agent_panel.dart';

class AgentApprovalCard extends ConsumerStatefulWidget {
  const AgentApprovalCard({super.key, required this.approval});
  final AgentApproval approval;

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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.09),
        border: Border.all(color: context.colors.warning),
        borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: context.colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.tr('agent.approval.title'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.trf('agent.approval.description', [
              item.hostName ?? '-',
              _toolLabel(l, item.tool),
            ]),
          ),
          if (item.effect != null) ...[
            const SizedBox(height: 6),
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
            const SizedBox(height: 8),
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
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                item.risk!['reason'].toString(),
                style: TextStyle(color: context.colors.danger),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => ref
                    .read(agentControllerProvider.notifier)
                    .approve(item.requestId, true),
                child: Text(l.tr('agent.approval.allow')),
              ),
              if (item.grantable)
                OutlinedButton(
                  onPressed: () => ref
                      .read(agentControllerProvider.notifier)
                      .approve(item.requestId, true, scope: 'session'),
                  child: Text(l.tr('agent.approval.allowSession')),
                ),
              TextButton(
                onPressed: () => ref
                    .read(agentControllerProvider.notifier)
                    .approve(item.requestId, false),
                child: Text(
                  l.tr('agent.approval.deny'),
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
