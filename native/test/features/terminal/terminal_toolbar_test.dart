import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/terminal_toolbar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Column(children: [const Spacer(), child])),
      );

  testWidgets('emits expected escape sequences', (tester) async {
    final inputs = <String>[];

    await tester.pumpWidget(wrap(TerminalToolbar(
      onInput: inputs.add,
      controller: null,
    )));

    Future<void> tap(String label) async {
      final finder = find.byKey(Key('toolbar-$label'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
    }

    await tap('Esc');
    await tap('Tab');
    await tap('Up');
    await tap('Down');
    await tap('Left');
    await tap('Right');
    await tap('PgUp');
    await tap('PgDn');
    await tester.pump();

    expect(inputs, [
      '\x1b',
      '\t',
      '\x1b[A',
      '\x1b[B',
      '\x1b[D',
      '\x1b[C',
      '\x1b[5~',
      '\x1b[6~',
    ]);
  });
}
