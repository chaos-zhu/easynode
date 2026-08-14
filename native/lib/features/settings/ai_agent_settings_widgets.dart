part of 'ai_agent_settings_page.dart';

String _providerLabel(String provider) => switch (provider) {
  'anthropic' => 'Anthropic',
  'google' => 'Google',
  _ => 'OpenAI Compatible',
};

class _SettingsChoiceRow extends StatelessWidget {
  const _SettingsChoiceRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.chip,
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
              ),
              child: Icon(icon, size: 20, color: context.colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: context.colors.softMuted),
          ],
        ),
      ),
    ),
  );
}

class _ModelSelectionRow extends StatelessWidget {
  const _ModelSelectionRow({
    required this.models,
    required this.invalid,
    required this.onTap,
  });

  final List<String> models;
  final bool invalid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _FieldLabel(text: l.tr('agent.settings.models'))),
            ],
          ),
          const SizedBox(height: 7),
          Material(
            color: context.colors.chip,
            borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
            child: InkWell(
              key: const Key('agent-models-row'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AgentUiTokens.radiusSmall,
                  ),
                  border: Border.all(
                    color: invalid
                        ? context.colors.danger
                        : context.colors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.memory_outlined,
                      size: 19,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        models.isEmpty
                            ? l.tr('agent.settings.selectModels')
                            : models.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: models.isEmpty
                              ? context.colors.muted
                              : context.colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: context.colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (invalid) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                l.tr('agent.settings.modelsRequired'),
                style: TextStyle(color: context.colors.danger, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.monospace = false,
    this.suffix,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool monospace;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          autocorrect: !obscureText,
          enableSuggestions: !obscureText,
          style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
          decoration: _fieldDecoration(
            context,
            hintText: hintText,
            suffix: suffix,
          ),
          validator: validator,
        ),
      ],
    ),
  );
}

class _LimitsRow extends StatelessWidget {
  const _LimitsRow({required this.contextLimit, required this.maxSteps});

  final TextEditingController contextLimit;
  final TextEditingController maxSteps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final contextField = _CompactNumberField(
      label: l.tr('agent.settings.contextLimit'),
      controller: contextLimit,
      validator: (value) => (int.tryParse(value ?? '') ?? 0) >= 1024
          ? null
          : l.tr('agent.settings.contextLimitInvalid'),
    );
    final stepsField = _CompactNumberField(
      label: l.tr('agent.settings.maxSteps'),
      controller: maxSteps,
      validator: (value) {
        final parsed = int.tryParse(value ?? '') ?? 0;
        return parsed >= 1 && parsed <= 50
            ? null
            : l.tr('agent.settings.maxStepsInvalid');
      },
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              children: [contextField, const SizedBox(height: 16), stepsField],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: contextField),
              const SizedBox(width: 12),
              Expanded(child: stepsField),
            ],
          );
        },
      ),
    );
  }
}

class _CompactNumberField extends StatelessWidget {
  const _CompactNumberField({
    required this.label,
    required this.controller,
    required this.validator,
  });

  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FieldLabel(text: label),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: _fieldDecoration(context),
        validator: validator,
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: context.colors.muted,
    ),
  );
}

InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hintText,
  Widget? suffix,
}) => InputDecoration(
  hintText: hintText,
  suffixIcon: suffix,
  filled: true,
  fillColor: context.colors.chip,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    borderSide: BorderSide(color: context.colors.primary, width: 1.5),
  ),
);

class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(Icons.dns_outlined, color: context.colors.muted),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(color: context.colors.muted)),
      ],
    ),
  );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: context.colors.card,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.border)),
          ),
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.fontOnPrimary,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(l.tr('common.save')),
          ),
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.colors.dangerSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                color: context.colors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.tr('common.retry')),
            ),
          ],
        ),
      ),
    );
  }
}
