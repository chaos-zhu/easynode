part of 'ai_agent_settings_page.dart';

class _HostPolicySummaryRow extends StatelessWidget {
  const _HostPolicySummaryRow({
    super.key,
    required this.policy,
    required this.onTap,
  });

  final AgentHostPolicy policy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final summary = policy.enabled
        ? '${_effectLabel(l, policy.maxEffect)} · ${_modeLabel(l, policy.maxMode)}'
        : l.tr('agent.settings.hostDisabled');
    return _SettingsChoiceRow(
      icon: Icons.dns_outlined,
      label: policy.name,
      subtitle: policy.address,
      value: summary,
      onTap: onTap,
    );
  }
}

class _HostPolicyEditorSheet extends StatefulWidget {
  const _HostPolicyEditorSheet({required this.policy, required this.onChanged});

  final AgentHostPolicy policy;
  final ValueChanged<AgentHostPolicy> onChanged;

  @override
  State<_HostPolicyEditorSheet> createState() => _HostPolicyEditorSheetState();
}

class _HostPolicyEditorSheetState extends State<_HostPolicyEditorSheet> {
  late AgentHostPolicy policy = widget.policy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.68)
        .clamp(400.0, 680.0)
        .toDouble();
    return SizedBox(
      height: height,
      child: AgentSelectionSheetFrame(
        title: l.tr('agent.settings.editHostPolicy'),
        icon: Icons.dns_outlined,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _HostIdentityCard(policy: policy),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      title: Text(
                        l.tr('agent.settings.allowHost'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(l.tr('agent.settings.allowHostHint')),
                      value: policy.enabled,
                      onChanged: (value) =>
                          _update(policy.copyWith(enabled: value)),
                    ),
                  ),
                  if (policy.enabled) ...[
                    Divider(height: 1, color: context.colors.border),
                    _SheetChoiceRow(
                      icon: Icons.edit_note_outlined,
                      label: l.tr('agent.settings.maxEffect'),
                      value: _effectLabel(l, policy.maxEffect),
                      onTap: _pickEffect,
                    ),
                    Divider(height: 1, color: context.colors.border),
                    _SheetChoiceRow(
                      icon: Icons.shield_outlined,
                      label: l.tr('agent.settings.maxMode'),
                      value: _modeLabel(l, policy.maxMode),
                      onTap: _pickMode,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickEffect() async {
    final l = AppLocalizations.of(context);
    final result = await showAgentSingleSelectionSheet<String>(
      context: context,
      title: l.tr('agent.settings.maxEffect'),
      icon: Icons.edit_note_outlined,
      selected: policy.maxEffect,
      options: [
        AgentSelectionOption(
          value: 'read',
          title: l.tr('agent.effect.read'),
          subtitle: l.tr('agent.settings.effect.readHint'),
          icon: Icons.visibility_outlined,
        ),
        AgentSelectionOption(
          value: 'write',
          title: l.tr('agent.effect.write'),
          subtitle: l.tr('agent.settings.effect.writeHint'),
          icon: Icons.edit_outlined,
        ),
      ],
    );
    if (result != null && mounted) {
      _update(policy.copyWith(maxEffect: result));
    }
  }

  Future<void> _pickMode() async {
    final l = AppLocalizations.of(context);
    final result = await showAgentSingleSelectionSheet<String>(
      context: context,
      title: l.tr('agent.settings.maxMode'),
      icon: Icons.shield_outlined,
      selected: policy.maxMode,
      options: const ['review', 'assist', 'authorized']
          .map(
            (mode) => AgentSelectionOption(
              value: mode,
              title: _modeLabel(l, mode),
              subtitle: _modeDescription(l, mode),
              icon: _modeIcon(mode),
            ),
          )
          .toList(growable: false),
    );
    if (result != null && mounted) {
      _update(policy.copyWith(maxMode: result));
    }
  }

  void _update(AgentHostPolicy value) {
    setState(() => policy = value);
    widget.onChanged(value);
  }
}

class _HostIdentityCard extends StatelessWidget {
  const _HostIdentityCard({required this.policy});
  final AgentHostPolicy policy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
      border: Border.all(color: context.colors.border),
    ),
    child: Row(
      children: [
        Icon(Icons.dns_outlined, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                policy.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                policy.address,
                style: TextStyle(
                  color: context.colors.muted,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SheetChoiceRow extends StatelessWidget {
  const _SheetChoiceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, color: context.colors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(value),
      trailing: Icon(
        Icons.keyboard_arrow_up_rounded,
        color: context.colors.muted,
      ),
      onTap: onTap,
    ),
  );
}

String _effectLabel(AppLocalizations l, String effect) =>
    effect == 'read' ? l.tr('agent.effect.read') : l.tr('agent.effect.write');

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
