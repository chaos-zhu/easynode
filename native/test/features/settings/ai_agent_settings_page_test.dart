import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/settings/ai_agent_settings_page.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAgentSettingsNotifier extends AgentSettingsNotifier {
  static int saveCalls = 0;
  static int discoverCalls = 0;

  @override
  Future<AgentSettingsData> build() async => AgentSettingsData(
    config: AgentProviderConfig(
      apiUrl: 'https://api.openai.com/v1',
      apiKey: 'secret',
      models: const ['gpt-5.4', 'gpt-5.6'],
    ),
    hostPolicies: const [
      AgentHostPolicy(
        hostId: 'host-1',
        name: 'Production server with a long name',
        address: '192.168.100.200:22',
      ),
    ],
  );

  @override
  Future<void> saveSettings({
    required AgentProviderConfig config,
    required List<AgentHostPolicy> hostPolicies,
    required List<AgentHostPolicy> changedHostPolicies,
  }) async {
    saveCalls += 1;
  }

  @override
  Future<List<String>> discoverModels({
    required String apiUrl,
    required String apiKey,
  }) async {
    discoverCalls += 1;
    return const ['gpt-discovered'];
  }
}

class _FakeDisabledSettingsNotifier extends AgentSettingsNotifier {
  static int saveCalls = 0;

  @override
  Future<AgentSettingsData> build() async => AgentSettingsData(
    config: AgentProviderConfig(
      apiUrl: 'https://api.openai.com/v1',
      apiKey: 'secret',
      models: const ['gpt-5.6'],
      nativeAgentEnabled: false,
    ),
    hostPolicies: const [],
  );

  @override
  Future<void> saveSettings({
    required AgentProviderConfig config,
    required List<AgentHostPolicy> hostPolicies,
    required List<AgentHostPolicy> changedHostPolicies,
  }) async {
    saveCalls += 1;
  }
}

Widget _app({double textScale = 1}) => ProviderScope(
  overrides: [
    agentSettingsProvider.overrideWith(_FakeAgentSettingsNotifier.new),
  ],
  child: MaterialApp(
    locale: const Locale('zh'),
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
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const AiAgentSettingsPage(),
  ),
);

void main() {
  testWidgets('settings stay usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app(textScale: 1.4));
    await tester.pumpAndSettle();

    expect(find.text('显示全局 AI 助手'), findsOneWidget);
    expect(find.text('OpenAI Compatible'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Production server with a long name'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Production server with a long name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider and host policy use sheets without eager saves', (
    tester,
  ) async {
    _FakeAgentSettingsNotifier.saveCalls = 0;
    _FakeAgentSettingsNotifier.discoverCalls = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(
      find.text('Provider、模型和主机策略与 Web 共用；Native 入口开关只影响 Native 应用。'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('agent-provider-row')));
    await tester.pumpAndSettle();
    expect(find.text('选择 Provider'), findsOneWidget);
    expect(find.byKey(const Key('agent-selection-search')), findsNothing);
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Production server with a long name'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Production server with a long name'));
    await tester.pumpAndSettle();
    expect(find.text('允许 AI 使用此主机'), findsOneWidget);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(_FakeAgentSettingsNotifier.saveCalls, 0);
    expect(find.text('已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model sheet supports search and custom model IDs', (
    tester,
  ) async {
    _FakeAgentSettingsNotifier.discoverCalls = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('agent-models-row')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('获取模型'), findsNothing);
    await tester.tap(find.byKey(const Key('agent-models-row')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-selection-search')), findsOneWidget);
    expect(find.text('已选 2 个'), findsOneWidget);
    expect(find.text('全不选'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
    expect(find.byTooltip('获取模型'), findsOneWidget);
    expect(find.byTooltip('输入自定义模型 ID'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-selection-load-options')));
    await tester.pumpAndSettle();
    expect(_FakeAgentSettingsNotifier.discoverCalls, 1);
    expect(find.text('gpt-discovered'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-selection-toggle-all')));
    await tester.pump();
    expect(find.text('已选 3 个'), findsOneWidget);
    expect(find.text('全不选'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('agent-selection-search')),
      'gpt-5.6',
    );
    await tester.pump();
    expect(find.text('取消选择搜索结果'), findsOneWidget);
    expect(find.text('gpt-5.6'), findsWidgets);
    expect(find.text('gpt-5.4'), findsNothing);
    await tester.enterText(find.byKey(const Key('agent-selection-search')), '');
    await tester.tap(find.byKey(const Key('agent-selection-add-custom')));
    await tester.pumpAndSettle();
    expect(find.text('输入 Provider 支持的准确模型 ID，添加后将立即选中。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('agent-selection-custom-value')),
      'custom-model-v1',
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.textContaining('custom-model-v1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful save returns without a success toast', (
    tester,
  ) async {
    _FakeDisabledSettingsNotifier.saveCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentSettingsProvider.overrideWith(_FakeDisabledSettingsNotifier.new),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const AiAgentSettingsPage(),
                    ),
                  ),
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(_FakeDisabledSettingsNotifier.saveCalls, 1);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
