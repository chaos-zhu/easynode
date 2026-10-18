import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/features/ai_agent/agent_ui_tokens.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tool card uses status styling and custom expansion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const part = AgentToolPart(
      toolCallId: 'tool-1',
      tool: 'exec_command',
      input: {'command': 'uptime'},
      status: AgentToolStatus.done,
      output: {'stdout': 'all good'},
      targetHost: AgentTargetHost(
        hostId: 'host-1',
        name: 'Production server with a long name',
        address: '10.0.0.1:2222',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
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
        home: const Scaffold(body: AgentToolCard(part: part)),
      ),
    );
    await tester.pump();

    expect(find.text('Run command'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(
      find.text(
        'Target host: Production server with a long name · 10.0.0.1:2222',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Production server with a long name · 10.0.0.1:2222'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('all good'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-tool-toggle-tool-1')));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('all good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long tool details are height limited and scrollable', (
    tester,
  ) async {
    final output = List.generate(
      100,
      (index) => 'Output line $index',
    ).join('\n');
    final part = AgentToolPart(
      toolCallId: 'long-tool',
      tool: 'exec_command',
      input: const {'command': 'generate-long-output'},
      status: AgentToolStatus.done,
      output: {'stdout': output},
    );
    await tester.pumpWidget(
      MaterialApp(
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
        home: Scaffold(body: AgentToolCard(part: part)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('agent-tool-toggle-long-tool')));
    await tester.pumpAndSettle();

    final scroll = find.byKey(
      const ValueKey('agent-tool-details-scroll-long-tool'),
    );
    expect(
      tester.getSize(scroll).height,
      AgentUiTokens.messagePartContentMaxHeight,
    );
    expect(tester.widget<SingleChildScrollView>(scroll).primary, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MCP tool card shows provider and remote display name', (
    tester,
  ) async {
    const part = AgentToolPart(
      toolCallId: 'mcp-tool',
      tool: 'mcp_anysearch_search_1234',
      input: {'query': 'EasyNode'},
      status: AgentToolStatus.done,
      output: {'content': 'ok'},
      toolInfo: {
        'source': 'mcp',
        'providerName': 'AnySearch',
        'displayName': 'Search',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
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
        home: const Scaffold(body: AgentToolCard(part: part)),
      ),
    );
    await tester.pump();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('MCP · AnySearch'), findsOneWidget);
    expect(find.text('EasyNode'), findsOneWidget);
  });
}
