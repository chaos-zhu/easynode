part of 'agent_panel.dart';

class AgentPanelBatchPreview extends StatelessWidget {
  const AgentPanelBatchPreview({super.key, required this.preview});
  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = mapList(preview['items']);
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.trf('agent.panel.count', [items.length])),
          for (final item in items)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                item['name']?.toString() ?? '',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                item['id']?.toString() ?? '',
                style: const TextStyle(fontSize: 11),
              ),
              children: [
                for (final change in mapList(item['changes']))
                  _DetailBlock(
                    label: l.tr('agent.panel.field.${change['field']}'),
                    text:
                        change['diff']?.toString() ??
                        '${l.tr('agent.panel.before')}: ${jsonEncode(change['before'])}\n${l.tr('agent.panel.after')}: ${jsonEncode(change['after'])}',
                  ),
                if (item['group'] is Map)
                  Text(
                    l.trf('agent.panel.group', [
                      stringMap(item['group'])['name'],
                    ]),
                  ),
                if (mapList(item['members']).isNotEmpty)
                  _DetailBlock(
                    label: l.tr('agent.panel.moveDefault'),
                    text: mapList(
                      item['members'],
                    ).map((member) => member['name']).join('\n'),
                  ),
                if (mapList(item['affectedTasks']).isNotEmpty)
                  _DetailBlock(
                    label: l.tr(
                      preview['action'] == 'delete'
                          ? 'agent.panel.disableTasks'
                          : 'agent.panel.updateTasks',
                    ),
                    text: mapList(item['affectedTasks'])
                        .map((task) => '${task['name']} (${task['taskId']})')
                        .join('\n'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
