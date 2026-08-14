import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tool card uses status styling and custom expansion', (
    tester,
  ) async {
    const part = AgentToolPart(
      toolCallId: 'tool-1',
      tool: 'exec_command',
      input: {'command': 'uptime'},
      status: AgentToolStatus.done,
      output: {'stdout': 'all good'},
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
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('all good'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-tool-toggle-tool-1')));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('all good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
