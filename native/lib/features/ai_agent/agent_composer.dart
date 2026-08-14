part of 'agent_panel.dart';

class _AgentComposer extends ConsumerWidget {
  const _AgentComposer({
    required this.controller,
    required this.state,
    required this.onSend,
  });

  final TextEditingController controller;
  final AgentState state;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hosts = ref.watch(agentHostPoliciesProvider);
    return Material(
      color: context.colors.card,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: l.tr('agent.inputHint'),
                  filled: true,
                  fillColor: context.colors.chip,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AgentUiTokens.radiusMedium,
                    ),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: state.conversation.running
                      ? IconButton(
                          tooltip: l.tr('agent.stop'),
                          onPressed: ref
                              .read(agentControllerProvider.notifier)
                              .stop,
                          icon: Icon(
                            Icons.stop_circle,
                            color: context.colors.danger,
                          ),
                        )
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) => IconButton(
                            tooltip: l.tr('agent.send'),
                            onPressed: state.canSendDraft(value.text)
                                ? onSend
                                : null,
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ComposerPickerButton(
                      icon: Icons.shield_outlined,
                      label: _modeLabel(l, state.mode),
                      tooltip: l.tr('agent.selectMode'),
                      enabled: !state.conversation.running,
                      onTap: () => _pickMode(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ComposerPickerButton(
                      icon: Icons.memory_outlined,
                      label: state.modelId.isEmpty
                          ? l.tr('agent.model')
                          : state.modelId,
                      tooltip: l.tr('agent.selectModel'),
                      enabled:
                          !state.conversation.running &&
                          state.models.isNotEmpty,
                      onTap: () => _pickModel(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: l.tr('agent.hosts'),
                    onPressed: state.conversation.running
                        ? null
                        : () => _pickHosts(context, ref, hosts, state.hostIds),
                    icon: Badge(
                      isLabelVisible: state.hostIds.isNotEmpty,
                      label: Text('${state.hostIds.length}'),
                      child: const Icon(Icons.dns_outlined),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMode(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final current = ref.read(agentControllerProvider);
    final result = await showAgentSingleSelectionSheet<String>(
      context: context,
      title: l.tr('agent.selectMode'),
      icon: Icons.shield_outlined,
      selected: current.mode,
      options: current.presets
          .map(
            (preset) => AgentSelectionOption(
              value: preset.key,
              title: _modeLabel(l, preset.key),
              subtitle: _modeDescription(l, preset.key),
              icon: _modeIcon(preset.key),
            ),
          )
          .toList(growable: false),
    );
    if (result != null && context.mounted) {
      await runAgentAction(
        context,
        () => ref.read(agentControllerProvider.notifier).setMode(result),
      );
    }
  }

  Future<void> _pickModel(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final current = ref.read(agentControllerProvider);
    final result = await showAgentSingleSelectionSheet<String>(
      context: context,
      title: l.tr('agent.selectModel'),
      icon: Icons.memory_outlined,
      selected: current.modelId,
      searchable: true,
      searchHint: l.tr('agent.searchModels'),
      options: current.models
          .map(
            (model) => AgentSelectionOption(
              value: model,
              title: model,
              icon: Icons.memory_outlined,
            ),
          )
          .toList(growable: false),
    );
    if (result != null && context.mounted) {
      await runAgentAction(
        context,
        () => ref.read(agentControllerProvider.notifier).setModel(result),
      );
    }
  }

  Future<void> _pickHosts(
    BuildContext context,
    WidgetRef ref,
    List<AgentHostPolicy> hosts,
    List<String> selected,
  ) async {
    final l = AppLocalizations.of(context);
    final enabledIds = hosts
        .where((host) => host.enabled)
        .map((host) => host.hostId)
        .toSet();
    await showAgentMultiSelectionSheet<String>(
      context: context,
      title: l.tr('agent.selectHosts'),
      icon: Icons.dns_outlined,
      searchable: true,
      searchHint: l.tr('agent.searchHosts'),
      selected: selected.toSet().intersection(enabledIds),
      onSelectionChanged: (result) {
        ref.read(agentControllerProvider.notifier).setHosts(result.toList());
      },
      options: hosts
          .map(
            (host) => AgentSelectionOption(
              value: host.hostId,
              title: host.name,
              subtitle: host.enabled
                  ? host.address
                  : l.tr('agent.hostDisabled'),
              icon: Icons.dns_outlined,
              enabled: host.enabled,
              searchText: host.address,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ComposerPickerButton extends StatelessWidget {
  const _ComposerPickerButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: context.colors.chip,
      borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: enabled
                      ? context.colors.primary
                      : context.colors.softMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? context.colors.text
                          : context.colors.softMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: context.colors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _modeLabel(AppLocalizations l, String mode) => switch (mode) {
  'assist' => l.tr('agent.mode.assist'),
  'authorized' => l.tr('agent.mode.authorized'),
  _ => l.tr('agent.mode.review'),
};

String _modeDescription(AppLocalizations l, String mode) => switch (mode) {
  'assist' => l.tr('agent.mode.assistDescription'),
  'authorized' => l.tr('agent.mode.authorizedDescription'),
  _ => l.tr('agent.mode.reviewDescription'),
};

IconData _modeIcon(String mode) => switch (mode) {
  'assist' => Icons.visibility_outlined,
  'authorized' => Icons.bolt_outlined,
  _ => Icons.fact_check_outlined,
};
