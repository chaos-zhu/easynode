import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/ai_agent/agent_models.dart';
import 'package:easynode_native/features/ai_agent/agent_panel.dart';
import 'package:easynode_native/features/ai_agent/agent_reducer.dart';
import 'package:easynode_native/features/ai_agent/agent_repository.dart';
import 'package:easynode_native/features/ai_agent/agent_socket_client.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long conversation offers one-tap scrolling to the bottom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = AppStorage(await SharedPreferences.getInstance());
    final notifier = _FakeAgentStateNotifier(_TestAgentDeps(storage));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [agentControllerProvider.overrideWith((ref) => notifier)],
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
          home: const Scaffold(body: AgentPanel(showHeader: false)),
        ),
      ),
    );
    await tester.pump();

    final messages = List.generate(
      30,
      (index) => AgentMessage(
        id: 'assistant-$index',
        role: AgentMessageRole.assistant,
        parts: [
          AgentTextPart(
            List.generate(
              index % 7 + 1,
              (line) => 'Response $index, variable-height line $line',
            ).join('\n'),
          ),
        ],
        createdAt: index,
      ),
    );
    notifier.showConversation(AgentConversationState(messages: messages));
    await tester.pumpAndSettle();

    const buttonKey = Key('agent-scroll-to-bottom');
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.reverse, isTrue);
    expect(find.byKey(buttonKey), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-message-assistant-29')),
      findsOneWidget,
    );
    expect(
      list.controller!.position.pixels,
      list.controller!.position.minScrollExtent,
    );

    list.controller!.jumpTo(list.controller!.position.minScrollExtent + 320);
    await tester.pumpAndSettle();

    expect(find.byKey(buttonKey), findsOneWidget);
    expect(find.byTooltip('Scroll to bottom'), findsOneWidget);
    expect(
      list.controller!.position.pixels -
          list.controller!.position.minScrollExtent,
      greaterThan(40),
    );
    final detachedPixels = list.controller!.position.pixels;

    final streamedMessages = [
      ...messages,
      const AgentMessage(
        id: 'assistant-detached-update',
        role: AgentMessageRole.assistant,
        parts: [AgentTextPart('Fast output while the user is reading')],
        createdAt: 31,
      ),
    ];

    notifier.showConversation(
      AgentConversationState(messages: streamedMessages),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(buttonKey), findsOneWidget);
    expect(list.controller!.position.pixels, closeTo(detachedPixels, 0.01));

    notifier.showConversation(
      AgentConversationState(
        messages: [
          ...messages,
          AgentMessage(
            id: 'assistant-detached-update',
            role: AgentMessageRole.assistant,
            parts: [
              AgentTextPart(
                List.generate(
                  12,
                  (line) => 'Streaming line $line while reading above',
                ).join('\n'),
              ),
            ],
            createdAt: 31,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(buttonKey), findsOneWidget);
    expect(list.controller!.position.pixels, closeTo(detachedPixels, 0.01));

    await tester.tap(find.byKey(buttonKey));
    notifier.showConversation(
      AgentConversationState(
        messages: [
          ...streamedMessages,
          const AgentMessage(
            id: 'assistant-stream-update',
            role: AgentMessageRole.assistant,
            parts: [AgentTextPart('A new streamed response')],
            createdAt: 32,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byKey(buttonKey), findsNothing);
    expect(
      list.controller!.position.pixels,
      list.controller!.position.minScrollExtent,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      list.controller!.position.pixels,
      list.controller!.position.minScrollExtent,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending approvals use a dock and only show the queue head', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final storage = AppStorage(await SharedPreferences.getInstance());
    final notifier = _FakeAgentStateNotifier(_TestAgentDeps(storage));
    final now = DateTime.now().millisecondsSinceEpoch;
    notifier.showConversation(
      AgentConversationState(
        messages: const [
          AgentMessage(
            id: 'assistant-1',
            role: AgentMessageRole.assistant,
            parts: [AgentTextPart('I need approval')],
            createdAt: 1,
          ),
        ],
        pendingApprovals: [
          AgentApproval(
            requestId: 'approval-1',
            toolCallId: 'tool-1',
            tool: 'exec_command',
            input: {
              'command': List.generate(
                20,
                (index) => 'echo approval-line-$index',
              ).join('\n'),
            },
            createdAt: now,
          ),
          AgentApproval(
            requestId: 'approval-2',
            toolCallId: 'tool-2',
            tool: 'exec_command',
            input: const {'command': 'df -h'},
            createdAt: now,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [agentControllerProvider.overrideWith((ref) => notifier)],
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const Scaffold(body: AgentPanel(showHeader: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-approval-dock')), findsOneWidget);
    expect(find.byType(AgentApprovalCard), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-approval-approval-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-approval-approval-2')),
      findsNothing,
    );
    expect(find.text('1 more approvals pending'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ListView)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      find.byKey(const Key('agent-approval-actions-scroll')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(AgentApprovalCard),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _FakeAgentStateNotifier extends AgentStateNotifier {
  _FakeAgentStateNotifier(_TestAgentDeps deps)
    : super(
        repository: deps.repository,
        socket: deps.socket,
        storage: deps.storage,
      );

  @override
  Future<void> open() async {}

  void showConversation(AgentConversationState conversation) {
    state = state.copyWith(conversation: conversation);
  }
}

class _TestAgentDeps {
  _TestAgentDeps(this.storage) {
    final secureStorage = SecureAppStorage(const FlutterSecureStorage());
    final cookieStore = SessionCookieStore(secureStorage);
    repository = AgentRepository(
      ApiClient(serverAddress: 'http://localhost', cookieStore: cookieStore),
    );
    socket = AgentSocketClient(
      authSession: const AuthSession(
        serverAddress: 'http://localhost',
        username: 'tester',
        token: 'token',
        deviceId: 'device',
      ),
      cookieStore: cookieStore,
      certificateTrust: ServerCertificateTrustStore(secureStorage),
    );
  }

  final AppStorage storage;
  late final AgentRepository repository;
  late final AgentSocketClient socket;
}
