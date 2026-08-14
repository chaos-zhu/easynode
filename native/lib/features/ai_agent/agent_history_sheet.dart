part of 'agent_panel.dart';

class AgentHistorySheet extends ConsumerWidget {
  const AgentHistorySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentControllerProvider);
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        ListTile(
          title: Text(
            l.tr('agent.history'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: l.tr('agent.clearHistory'),
                onPressed: state.sessions.isEmpty
                    ? null
                    : () => _confirmClear(context, ref),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              IconButton(
                tooltip: l.tr('agent.newConversation'),
                onPressed: () {
                  ref.read(agentControllerProvider.notifier).newConversation();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.sessionsLoading
              ? const Center(child: CircularProgressIndicator())
              : state.sessions.isEmpty
              ? Center(child: Text(l.tr('agent.historyEmpty')))
              : ListView.builder(
                  itemCount: state.sessions.length,
                  itemBuilder: (context, index) {
                    final session = state.sessions[index];
                    return ListTile(
                      selected: session.id == state.conversation.sessionId,
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l.trf('agent.historyMeta', [session.messageCount]),
                      ),
                      onTap: () async {
                        final loaded = await runAgentAction(context, () async {
                          await ref
                              .read(agentControllerProvider.notifier)
                              .loadSession(session.id);
                          return true;
                        });
                        if (loaded == true && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) =>
                            _sessionAction(context, ref, session, action),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(l.tr('common.rename')),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l.tr('common.delete')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _sessionAction(
    BuildContext context,
    WidgetRef ref,
    AgentSessionSummary session,
    String action,
  ) async {
    if (action == 'delete') {
      final confirmed = await _confirm(context, 'agent.deleteSessionConfirm');
      if (context.mounted && confirmed == true) {
        await runAgentAction(
          context,
          () => ref
              .read(agentControllerProvider.notifier)
              .deleteSession(session.id),
        );
      }
      return;
    }
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).tr('common.rename')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context).tr('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (context.mounted && title != null && title.trim().isNotEmpty) {
      await runAgentAction(
        context,
        () => ref
            .read(agentControllerProvider.notifier)
            .renameSession(session.id, title),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(context, 'agent.clearHistoryConfirm');
    if (context.mounted && confirmed == true) {
      await runAgentAction(
        context,
        ref.read(agentControllerProvider.notifier).clearSessions,
      );
    }
  }

  Future<bool?> _confirm(BuildContext context, String key) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(AppLocalizations.of(context).tr(key)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context).tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppLocalizations.of(context).tr('common.confirm')),
        ),
      ],
    ),
  );
}
