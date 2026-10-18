import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/features/ai_agent/agent_ui_tokens.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approval details are height limited while actions stay visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final approval = AgentApproval(
      requestId: 'approval-1',
      toolCallId: 'tool-1',
      tool: 'write_file',
      hostName: 'Legacy name',
      targetHost: const AgentTargetHost(
        hostId: 'host-1',
        name: 'Production server with a long name',
        address: '10.0.0.1:2222',
      ),
      input: const {'path': '/tmp/example'},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      preview: {
        'diff': List.generate(100, (index) => 'Diff line $index').join('\n'),
      },
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
          home: Scaffold(body: AgentApprovalCard(approval: approval)),
        ),
      ),
    );
    await tester.pump();

    final scroll = find.byKey(const Key('agent-approval-details-scroll'));
    expect(
      tester.getSize(scroll).height,
      AgentUiTokens.messagePartContentMaxHeight,
    );
    expect(tester.widget<SingleChildScrollView>(scroll).primary, isFalse);
    expect(
      find.text(
        'Run Write file on Production server with a long name · 10.0.0.1:2222',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Legacy name'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Allow'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Deny'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('MCP approval names the provider and offers tool grant', (
    tester,
  ) async {
    final approval = AgentApproval(
      requestId: 'approval-mcp',
      toolCallId: 'tool-mcp',
      tool: 'mcp_anysearch_search',
      input: const {'query': 'EasyNode'},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      providerName: 'AnySearch',
      toolInfo: const {
        'source': 'mcp',
        'providerName': 'AnySearch',
        'displayName': 'Search',
      },
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
          home: Scaffold(body: AgentApprovalCard(approval: approval)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Run Search through AnySearch'), findsOneWidget);
    expect(find.text('Allow this tool for this session'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
