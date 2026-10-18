import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, String language) => ProviderScope(
  child: MaterialApp(
    locale: Locale(language),
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
    home: Scaffold(body: child),
  ),
);

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets(
      'panel approval has localized label and expandable diff ($language)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final approval = AgentApproval.fromEvent({
          'type': 'approval_request',
          'requestId': 'approval',
          'toolCallId': 'call',
          'tool': 'script_batch_update',
          'input': {},
          'grantable': false,
          'preview': {
            'type': 'panel_batch',
            'action': 'update',
            'items': [
              {
                'id': 's',
                'name': 'Application script',
                'changes': [
                  {
                    'field': 'command',
                    'before': 'echo old',
                    'after': 'echo new',
                    'diff': '-echo old\n+echo new',
                  },
                ],
                'affectedTasks': [
                  {'taskId': 't', 'name': 'Nightly task'},
                ],
              },
            ],
          },
        });
        await tester.pumpWidget(
          app(AgentApprovalCard(approval: approval), language),
        );
        await tester.pump();
        expect(
          find.text(
            language == 'en'
                ? 'Change panel data: Update scripts'
                : '修改面板数据：批量修改脚本',
          ),
          findsOneWidget,
        );
        expect(find.byType(ExpansionTile), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(
          find.widgetWithText(FilledButton, language == 'en' ? 'Allow' : '允许'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextButton, language == 'en' ? 'Deny' : '拒绝'),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'en' ? 'on -' : '将在 - 上执行'),
          findsNothing,
        );
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        expect(find.text('-echo old\n+echo new'), findsOneWidget);
        expect(find.text('Nightly task (t)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('tool card distinguishes partial results', (tester) async {
    await tester.pumpWidget(
      app(
        const AgentToolCard(
          part: AgentToolPart(
            toolCallId: 'call',
            tool: 'script_batch_create',
            input: {'items': []},
            status: AgentToolStatus.done,
            output: {
              'type': 'panel_batch_result',
              'status': 'partial',
              'completed': 1,
              'total': 3,
              'results': [
                {'id': 'a', 'name': 'A', 'status': 'completed'},
                {
                  'id': 'b',
                  'name': 'B',
                  'status': 'failed',
                  'error': 'offline',
                },
                {'id': 'c', 'name': 'C', 'status': 'not_executed'},
              ],
            },
          ),
        ),
        'en',
      ),
    );
    await tester.pump();
    expect(find.text('Partially completed · 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-tool-toggle-call')));
    await tester.pumpAndSettle();
    expect(find.textContaining('C (c): Not executed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
