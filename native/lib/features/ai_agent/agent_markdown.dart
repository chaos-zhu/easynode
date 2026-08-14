part of 'agent_panel.dart';

class _AgentMarkdown extends StatelessWidget {
  const _AgentMarkdown({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    final expression = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
    final widgets = <Widget>[];
    var cursor = 0;
    for (final match in expression.allMatches(data)) {
      if (match.start > cursor) {
        widgets.add(
          _markdownBody(context, data.substring(cursor, match.start)),
        );
      }
      widgets.add(
        _CodeBlock(language: match.group(1)!.trim(), code: match.group(2)!),
      );
      cursor = match.end;
    }
    if (cursor < data.length) {
      widgets.add(_markdownBody(context, data.substring(cursor)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _markdownBody(BuildContext context, String text) => MarkdownBody(
    data: text,
    selectable: true,
    onTapLink: (_, href, _) {
      if (href != null) unawaited(_openLink(context, href));
    },
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(color: context.colors.text, height: 1.55),
      code: TextStyle(
        fontFamily: 'monospace',
        color: context.colors.text,
        backgroundColor: context.colors.chip,
      ),
      blockquoteDecoration: BoxDecoration(
        color: context.colors.chip,
        border: Border(
          left: BorderSide(color: context.colors.primary, width: 3),
        ),
      ),
    ),
  );

  Future<void> _openLink(BuildContext context, String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        !const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
      showAgentError(
        context,
        AppLocalizations.of(context).tr('agent.linkOpenFailed'),
      );
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        showAgentError(
          context,
          AppLocalizations.of(context).tr('agent.linkOpenFailed'),
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAgentError(
          context,
          AppLocalizations.of(context).tr('agent.linkOpenFailed'),
        );
      }
    }
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.language, required this.code});
  final String language;
  final String code;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: context.colors.chip,
      border: Border.all(color: context.colors.border),
      borderRadius: BorderRadius.circular(AgentUiTokens.radiusSmall),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  language.isEmpty ? 'text' : language,
                  style: TextStyle(fontSize: 11, color: context.colors.muted),
                ),
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).tr('common.copy'),
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy_outlined, size: 16),
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SelectableText.rich(_highlightSpan(context)),
        ),
      ],
    ),
  );

  TextSpan _highlightSpan(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.5,
      color: context.colors.text,
    );
    final name = language.toLowerCase();
    if (name.isEmpty || _agentHighlighter.getLanguage(name) == null) {
      return TextSpan(text: code, style: base);
    }
    try {
      final result = _agentHighlighter.highlight(code: code, language: name);
      final renderer = TextSpanRenderer(base, _highlightTheme(context));
      result.render(renderer);
      return renderer.span ?? TextSpan(text: code, style: base);
    } catch (_) {
      return TextSpan(text: code, style: base);
    }
  }

  Map<String, TextStyle> _highlightTheme(BuildContext context) {
    final colors = context.colors;
    final normal = TextStyle(color: colors.text);
    final muted = TextStyle(color: colors.muted);
    final primary = TextStyle(color: colors.primary);
    final accent = TextStyle(color: colors.accent);
    final success = TextStyle(color: colors.success);
    final warning = TextStyle(color: colors.warning);
    final danger = TextStyle(color: colors.danger);
    return {
      'root': normal,
      for (final key in const [
        'doctag',
        'keyword',
        'meta-keyword',
        'template-tag',
        'template-variable',
        'type',
        'variable.language_',
      ])
        key: danger,
      for (final key in const [
        'title',
        'title.class_',
        'title.class_.inherited__',
        'title.function_',
      ])
        key: accent,
      for (final key in const [
        'attr',
        'attribute',
        'literal',
        'meta',
        'number',
        'operator',
        'variable',
        'selector-attr',
        'selector-class',
        'selector-id',
      ])
        key: primary,
      for (final key in const ['regexp', 'string', 'meta-string']) key: success,
      for (final key in const ['built_in', 'symbol', 'bullet']) key: warning,
      for (final key in const ['comment', 'code', 'formula']) key: muted,
      for (final key in const [
        'name',
        'quote',
        'selector-tag',
        'selector-pseudo',
        'addition',
      ])
        key: success,
      'subst': normal,
      'section': primary.copyWith(fontWeight: FontWeight.bold),
      'emphasis': normal.copyWith(fontStyle: FontStyle.italic),
      'strong': normal.copyWith(fontWeight: FontWeight.bold),
      'deletion': danger,
    };
  }
}
