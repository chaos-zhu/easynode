import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_overlay.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:easynode_native/state/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStorage> storage() async {
    SharedPreferences.setMockInitialValues({});
    return AppStorage(await SharedPreferences.getInstance());
  }

  Widget app({
    required AppStorage storage,
    required AgentNavigationObserver observer,
    bool enabled = true,
    WidgetBuilder? compactPageBuilder,
  }) {
    final navigatorKey = GlobalKey<NavigatorState>();
    return ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        nativeAgentEnabledProvider.overrideWithValue(enabled),
        agentKeepAliveProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
        home: Builder(
          builder: (context) => Stack(
            children: [
              Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const Key('open-dialog'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(content: Text('Blocking dialog')),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ),
              ),
              AgentGlobalOverlay(
                navigationObserver: observer,
                navigatorKey: navigatorKey,
                compactPageBuilder: compactPageBuilder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('shows entry when enabled and hides it for popup routes', (
    tester,
  ) async {
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(app(storage: prefs, observer: observer));
    await tester.pump();

    expect(find.byKey(const Key('agent-global-entry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('agent-global-entry')), findsNothing);

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-global-entry')), findsOneWidget);
  });

  testWidgets('does not build the entry when the server preference is off', (
    tester,
  ) async {
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(
      app(storage: prefs, observer: observer, enabled: false),
    );
    await tester.pump();

    expect(find.byKey(const Key('agent-global-entry')), findsNothing);
  });

  testWidgets('tap opens the compact panel through the root navigator', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(
      app(
        storage: prefs,
        observer: observer,
        compactPageBuilder: (_) => const Scaffold(
          body: Center(
            child: Text('Agent conversation', key: Key('agent-panel-test')),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('agent-global-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-panel-test')), findsOneWidget);
    expect(find.byKey(const Key('agent-global-entry')), findsNothing);

    Navigator.of(
      tester.element(find.byKey(const Key('agent-panel-test'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-global-entry')), findsOneWidget);
  });

  testWidgets('entry can be focused and activated from the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(
      app(
        storage: prefs,
        observer: observer,
        compactPageBuilder: (_) => const Scaffold(
          body: Text('Keyboard opened', key: Key('agent-keyboard-panel')),
        ),
      ),
    );
    await tester.pump();

    final entry = find.byKey(const Key('agent-global-entry'));
    Focus.of(tester.element(entry)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-keyboard-panel')), findsOneWidget);
  });

  testWidgets('snaps to an edge and persists its local position', (
    tester,
  ) async {
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(app(storage: prefs, observer: observer));
    await tester.pump();

    final entry = find.byKey(const Key('agent-global-entry'));
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getTopRight(entry).dx, closeTo(logicalWidth, 0.01));

    await tester.drag(entry, const Offset(-700, -120));
    await tester.pumpAndSettle();

    expect(prefs.agentEntrySide, 'left');
    expect(prefs.agentEntryY, inInclusiveRange(0.05, 0.95));
    expect(tester.getTopLeft(entry).dx, closeTo(0, 0.01));
  });

  testWidgets('animates to the nearest edge after release', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final prefs = await storage();
    final observer = AgentNavigationObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(app(storage: prefs, observer: observer));
    await tester.pump();

    final entry = find.byKey(const Key('agent-global-entry'));
    await tester.drag(entry, const Offset(-200, 0));
    await tester.pump();
    final releaseX = tester.getTopLeft(entry).dx;
    expect(releaseX, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 80));

    final transitioningX = tester.getTopLeft(entry).dx;
    expect(transitioningX, greaterThan(0));
    expect(transitioningX, lessThan(releaseX));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(entry).dx, closeTo(0, 0.01));
  });
}
