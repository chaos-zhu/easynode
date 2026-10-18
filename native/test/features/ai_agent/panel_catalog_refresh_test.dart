import 'dart:async';

import 'package:easynode_native/features/ai_agent/panel_catalog_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coalesces domains and preserves notifications during refresh', (
    tester,
  ) async {
    final calls = <Set<String>>[];
    final completion = Completer<void>();
    final queue = PanelCatalogRefresh(
      refresh: (domains) async {
        calls.add(domains);
        if (calls.length == 1) await completion.future;
      },
      onError: () => fail('Unexpected refresh failure'),
    );
    queue.schedule(['hosts', 'unknown']);
    queue.schedule(['hosts', 'scripts']);
    await tester.pump(const Duration(milliseconds: 101));
    expect(calls, [
      {'hosts', 'scripts'},
    ]);
    queue.schedule(['scheduled_tasks']);
    await tester.pump(const Duration(milliseconds: 101));
    expect(calls, hasLength(1));
    completion.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 101));
    expect(calls.last, {'scheduled_tasks'});
    queue.dispose();
  });

  testWidgets('reports refresh failure separately and cancels on disposal', (
    tester,
  ) async {
    var errors = 0;
    var calls = 0;
    final queue = PanelCatalogRefresh(
      refresh: (_) async {
        calls++;
        throw StateError('offline');
      },
      onError: () => errors++,
    );
    queue.schedule(['scripts']);
    await tester.pump(const Duration(milliseconds: 101));
    expect(errors, 1);
    queue.schedule(['hosts']);
    queue.dispose();
    await tester.pump(const Duration(milliseconds: 101));
    expect(calls, 1);
  });
}
