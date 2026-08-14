part of 'agent_panel.dart';

class AgentMessageView extends ConsumerWidget {
  const AgentMessageView({
    super.key,
    required this.message,
    required this.running,
    required this.waitingForModel,
  });

  final AgentMessage message;
  final bool running;
  final bool waitingForModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.role == AgentMessageRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 16),
          child: GestureDetector(
            onLongPress: running ? null : () => _showUserActions(context, ref),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.chip,
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusLarge),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: SelectableText(
                  message.text,
                  style: TextStyle(color: context.colors.text, height: 1.45),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final hasResponseText = message.parts.any(
      (part) => part is AgentTextPart && part.text.trim().isNotEmpty,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._messagePartWidgets(),
          if (waitingForModel)
            _AgentThinking(labelKey: 'agent.analyzingTools')
          else if (running && message.parts.isEmpty)
            _AgentThinking(labelKey: 'agent.thinking'),
          if (!running && hasResponseText)
            Wrap(
              spacing: AgentUiTokens.messageActionGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _AgentMessageAction(
                  tooltip: AppLocalizations.of(context).tr('common.copy'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: message.text)),
                  icon: Icons.copy_outlined,
                ),
                _AgentMessageAction(
                  tooltip: AppLocalizations.of(context).tr('agent.regenerate'),
                  onPressed: () async {
                    final error = await runAgentAction(
                      context,
                      () => ref
                          .read(agentControllerProvider.notifier)
                          .regenerate(message),
                    );
                    if (error != null && context.mounted) {
                      showAgentError(
                        context,
                        AppLocalizations.of(context).tr(error),
                      );
                    }
                  },
                  icon: Icons.refresh,
                ),
                _AgentMessageAction(
                  tooltip: AppLocalizations.of(context).tr('agent.fork'),
                  onPressed: () => runAgentAction(
                    context,
                    () => ref
                        .read(agentControllerProvider.notifier)
                        .fork(message),
                  ),
                  icon: Icons.call_split,
                ),
                if (message.usage != null)
                  _AgentMessageAction(
                    key: const Key('agent-usage-button'),
                    tooltip: AppLocalizations.of(
                      context,
                    ).tr('agent.usage.title'),
                    onPressed: () => _showUsage(context, message.usage!),
                    icon: Icons.info_outline,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _messagePartWidgets() {
    final widgets = <Widget>[];
    for (var index = 0; index < message.parts.length; index++) {
      final part = message.parts[index];
      final Widget? child = switch (part) {
        AgentReasoningPart() => _ReasoningBlock(
          key: ValueKey('agent-reasoning-$index'),
          part: part,
        ),
        AgentToolPart() => AgentToolCard(part: part),
        AgentTextPart() when part.text.isNotEmpty => _AgentMarkdown(
          data: part.text,
        ),
        _ => null,
      };
      if (child != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(
              bottom: AgentUiTokens.messagePartGap,
            ),
            child: child,
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _showUserActions(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.tr('agent.editMessage')),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l.tr('common.copy')),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
    } else if (action == 'edit' && context.mounted) {
      final content = await _editDialog(context, message.text);
      if (context.mounted && content != null && content.trim().isNotEmpty) {
        final error = await runAgentAction(
          context,
          () => ref
              .read(agentControllerProvider.notifier)
              .editAndResend(message, content),
        );
        if (error != null && context.mounted) {
          showAgentError(context, AppLocalizations.of(context).tr(error));
        }
      }
    }
  }

  Future<String?> _editDialog(BuildContext context, String initial) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgentEditMessageSheet(initial: initial),
    );
  }

  Future<void> _showUsage(BuildContext context, AgentUsage usage) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AgentUsageSheet(usage: usage),
      );
}

class _AgentMessageAction extends StatelessWidget {
  const _AgentMessageAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(
      width: AgentUiTokens.messageActionWidth,
      height: AgentUiTokens.messageActionHeight,
    ),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 18),
  );
}

class _AgentUsageSheet extends StatelessWidget {
  const _AgentUsageSheet({required this.usage});

  final AgentUsage usage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final metrics = <({String label, IconData icon, int value})>[
      (
        label: l.tr('agent.usage.input'),
        icon: Icons.login_rounded,
        value: usage.inputTokens,
      ),
      (
        label: l.tr('agent.usage.output'),
        icon: Icons.logout_rounded,
        value: usage.outputTokens,
      ),
      if (usage.cachedInputTokens > 0)
        (
          label: l.tr('agent.usage.cached'),
          icon: Icons.bolt_rounded,
          value: usage.cachedInputTokens,
        ),
      if (usage.reasoningTokens > 0)
        (
          label: l.tr('agent.usage.reasoning'),
          icon: Icons.psychology_outlined,
          value: usage.reasoningTokens,
        ),
    ];
    final height = (190 + metrics.length * 52).clamp(300, 460).toDouble();

    return SizedBox(
      height: height,
      child: AgentSelectionSheetFrame(
        title: l.tr('agent.usage.title'),
        icon: Icons.data_usage_rounded,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.chip,
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(
                        AgentUiTokens.radiusSmall,
                      ),
                    ),
                    child: Icon(
                      Icons.token_rounded,
                      color: context.colors.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.tr('agent.usage.total'),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    NumberFormat.decimalPattern(
                      locale,
                    ).format(usage.totalTokens),
                    style: TextStyle(
                      color: context.colors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(AgentUiTokens.radiusMedium),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < metrics.length; index++) ...[
                    _AgentUsageRow(
                      label: metrics[index].label,
                      icon: metrics[index].icon,
                      value: NumberFormat.decimalPattern(
                        locale,
                      ).format(metrics[index].value),
                    ),
                    if (index < metrics.length - 1)
                      Divider(
                        height: 1,
                        indent: 44,
                        color: context.colors.border,
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
}

class _AgentUsageRow extends StatelessWidget {
  const _AgentUsageRow({
    required this.label,
    required this.icon,
    required this.value,
  });

  final String label;
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: [
        Icon(icon, size: 17, color: context.colors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: context.colors.text)),
        ),
        Text(
          value,
          style: TextStyle(
            color: context.colors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _AgentEditMessageSheet extends StatefulWidget {
  const _AgentEditMessageSheet({required this.initial});

  final String initial;

  @override
  State<_AgentEditMessageSheet> createState() => _AgentEditMessageSheetState();
}

class _AgentEditMessageSheetState extends State<_AgentEditMessageSheet> {
  late final TextEditingController controller = TextEditingController(
    text: widget.initial,
  )..addListener(_handleChanged);

  bool get canSubmit => controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() => setState(() {});

  void _submit() {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewPadding.top - media.viewInsets.bottom;
    final preferredHeight = (media.size.height * 0.58).clamp(360.0, 560.0);
    final height = math
        .min(preferredHeight, math.max(240, availableHeight))
        .toDouble();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: AgentSelectionSheetFrame(
          title: l.tr('agent.editMessage'),
          icon: Icons.edit_note_rounded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.tr('agent.editMessageHint'),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): _submit,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): _submit,
                    },
                    child: TextField(
                      key: const Key('agent-edit-message-field'),
                      controller: controller,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: l.tr('agent.inputHint'),
                        filled: true,
                        fillColor: context.colors.card,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AgentUiTokens.radiusMedium,
                          ),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AgentUiTokens.radiusMedium,
                          ),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AgentUiTokens.radiusMedium,
                          ),
                          borderSide: BorderSide(
                            color: context.colors.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('agent-edit-message-submit'),
                  onPressed: canSubmit ? _submit : null,
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(l.tr('agent.editResendAction')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentThinking extends StatelessWidget {
  const _AgentThinking({required this.labelKey});
  final String labelKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          AppLocalizations.of(context).tr(labelKey),
          style: TextStyle(color: context.colors.muted),
        ),
      ],
    ),
  );
}

class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({super.key, required this.part});
  final AgentReasoningPart part;

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AgentUiTokens.radiusMedium);
    final background = expanded
        ? Color.alphaBlend(colors.primary.withValues(alpha: 0.035), colors.card)
        : colors.card;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(
          color: expanded
              ? colors.primary.withValues(alpha: 0.22)
              : colors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('agent-reasoning-toggle'),
                borderRadius: radius,
                onTap: () => setState(() => expanded = !expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AgentUiTokens.messagePartHeaderMinHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 17,
                          color: expanded ? colors.primary : colors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).tr('agent.reasoning'),
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: colors.muted,
                          ),
                        ),
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
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: SelectableText(
                      widget.part.text,
                      key: const Key('agent-reasoning-content'),
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
