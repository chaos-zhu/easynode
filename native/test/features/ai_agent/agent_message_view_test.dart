import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/features/ai_agent/agent_ui_tokens.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('markdown links have an activation handler', (tester) async {
    final message = AgentMessage(
      id: 'assistant-1',
      role: AgentMessageRole.assistant,
      parts: const [AgentTextPart('[Documentation](https://example.com)')],
      createdAt: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: false,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.onTapLink, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reasoning uses a lightweight expandable card', (tester) async {
    final message = AgentMessage(
      id: 'assistant-reasoning',
      role: AgentMessageRole.assistant,
      parts: const [AgentReasoningPart('Internal reasoning details')],
      createdAt: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: true,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-reasoning-0')), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byKey(const Key('agent-reasoning-content')), findsNothing);

    await tester.tap(find.byKey(const Key('agent-reasoning-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Internal reasoning details'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed message cards share height and outer spacing', (
    tester,
  ) async {
    final message = AgentMessage(
      id: 'assistant-card-layout',
      role: AgentMessageRole.assistant,
      parts: const [
        AgentReasoningPart('First reasoning'),
        AgentToolPart(
          toolCallId: 'layout-tool',
          tool: 'host_list',
          input: {},
          status: AgentToolStatus.done,
        ),
        AgentReasoningPart('Second reasoning'),
      ],
      createdAt: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: true,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final first = tester.getRect(
      find.byKey(const ValueKey('agent-reasoning-0')),
    );
    final tool = tester.getRect(
      find.byKey(const ValueKey('agent-tool-layout-tool')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('agent-reasoning-2')),
    );

    expect(first.height, tool.height);
    expect(tool.height, second.height);
    expect(tool.top - first.bottom, AgentUiTokens.messagePartGap);
    expect(second.top - tool.bottom, AgentUiTokens.messagePartGap);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool-only assistant steps do not show response actions', (
    tester,
  ) async {
    final message = AgentMessage(
      id: 'assistant-tool-only',
      role: AgentMessageRole.assistant,
      parts: const [
        AgentToolPart(
          toolCallId: 'tool-only',
          tool: 'host_list',
          input: {},
          status: AgentToolStatus.done,
        ),
      ],
      createdAt: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: false,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Copy'), findsNothing);
    expect(find.byTooltip('Regenerate'), findsNothing);
    expect(find.byTooltip('Fork conversation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usage info button opens token details', (tester) async {
    final message = AgentMessage(
      id: 'assistant-usage',
      role: AgentMessageRole.assistant,
      parts: const [AgentTextPart('Completed')],
      createdAt: 1,
      usage: const AgentUsage(
        inputTokens: 800,
        outputTokens: 434,
        totalTokens: 1234,
        cachedInputTokens: 200,
        reasoningTokens: 50,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: false,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final actionFinders = [
      find.byTooltip('Copy'),
      find.byTooltip('Regenerate'),
      find.byTooltip('Fork conversation'),
      find.byTooltip('Token usage'),
    ];
    for (final action in actionFinders) {
      expect(
        tester.getSize(action),
        const Size(
          AgentUiTokens.messageActionWidth,
          AgentUiTokens.messageActionHeight,
        ),
      );
    }
    final actionRowWidth =
        tester.getRect(actionFinders.last).right -
        tester.getRect(actionFinders.first).left;
    expect(
      actionRowWidth,
      AgentUiTokens.messageActionWidth * actionFinders.length +
          AgentUiTokens.messageActionGap * (actionFinders.length - 1),
    );

    await tester.tap(find.byKey(const Key('agent-usage-button')));
    await tester.pumpAndSettle();

    expect(find.text('Token usage'), findsOneWidget);
    expect(find.text('Total tokens'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('Cached input'), findsOneWidget);
    expect(find.text('Reasoning tokens'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit and resend uses the themed bottom sheet', (tester) async {
    final message = AgentMessage(
      id: 'user-edit',
      role: AgentMessageRole.user,
      parts: const [AgentTextPart('Original prompt')],
      createdAt: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [AppColorTheme.defaultLight],
          ),
          home: Scaffold(
            body: AgentMessageView(
              message: message,
              running: false,
              waitingForModel: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final messageGesture = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .firstWhere((widget) => widget.onLongPress != null);
    messageGesture.onLongPress!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit and resend'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('agent-edit-message-field')), findsOneWidget);
    expect(
      find.text(
        'Update this message to regenerate the conversation from this point.',
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key('agent-edit-message-field')),
    );
    expect(field.controller?.text, 'Original prompt');

    await tester.enterText(
      find.byKey(const Key('agent-edit-message-field')),
      '',
    );
    await tester.pump();
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('agent-edit-message-submit')),
    );
    expect(submit.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
