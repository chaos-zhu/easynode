import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/terminal_toolbar.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Column(children: [const Spacer(), child])));

  testWidgets('emits expected escape sequences', (tester) async {
    final inputs = <String>[];
    var disconnected = 0;

    await tester.pumpWidget(wrap(TerminalToolbar(
      onInput: inputs.add,
      onDisconnect: () => disconnected++,
    )));

    // Find toolbar buttons via their keys.
    Future<void> tap(String label) async {
      final finder = find.byKey(Key('toolbar-$label'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
    }

    await tap('Esc');
    await tap('Tab');
    await tap('Enter');
    await tap('Ctrl-C');
    await tap('Ctrl-D');
    await tap('断开');
    await tester.pump();

    expect(inputs, ['\x1b', '\t', '\r', '\x03', '\x04']);
    expect(disconnected, 1);
  });
}
