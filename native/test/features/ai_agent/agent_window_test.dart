import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide window stays above the software keyboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const [AppColorTheme.defaultLight],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
          child: child!,
        ),
        home: AgentWideDialog(
          panelBuilder: (_) => const ColoredBox(
            color: Colors.transparent,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    final rect = tester.getRect(find.byKey(const Key('agent-wide-window')));
    expect(rect.bottom, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });
}
