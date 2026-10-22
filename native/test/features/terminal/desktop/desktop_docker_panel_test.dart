import 'dart:async';
import 'package:re_editor/re_editor.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/docker/docker_container.dart';
import 'package:easynode_native/features/docker/docker_session_manager.dart';
import 'package:easynode_native/features/docker/docker_socket_client.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_docker_panel.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'desktop_test_support.dart';

class _Client implements DockerSocketClient {
  final results = StreamController<DockerOperationResult>.broadcast();
  @override
  Stream<DockerOperationResult> get operationStream => results.stream;
  @override
  void refresh() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager extends DockerSessionManager {
  final state = DockerSessionState(
    server: host('one'),
    client: _Client(),
    status: DockerConnectionStatus.connected,
    loading: false,
    containers: List.generate(
      4,
      (index) => DockerContainer.fromJson({
        'id': 'abcdefabcdef$index',
        'name': 'container-$index',
        'image': 'nginx:latest',
        'status': 'running',
        'ports': ['0.0.0.0:8080->80/tcp'],
      }),
    ),
  );
  final operations = <String>[];
  @override
  DockerSessionState? sessionFor(String? hostId) => state;
  @override
  bool isConnected(String hostId) => true;
  @override
  void stop(DockerContainer container, {String? hostId}) {
    operations.add('stop:${container.id}:$hostId');
  }

  @override
  void getLogs(DockerContainer container, {String? hostId}) {
    state.logs = 'container log output';
    notifyListeners();
  }

  @override
  void refreshLogs(DockerContainer container, {String? hostId}) {}
}

void main() {
  for (final width in [650.0, 1100.0]) {
    testWidgets('Docker cards, shell action and logs work at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final manager = _Manager();
      final commands = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isPlusActiveProvider.overrideWithValue(true),
            desktopTerminalPreferencesProvider.overrideWith(
              (ref) => DesktopTerminalPreferences((_) async {}, ''),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              useMaterial3: true,
              extensions: const [AppColorTheme.defaultLight],
            ),
            home: Scaffold(
              body: DesktopDockerPanel(
                server: manager.state.server,
                manager: manager,
                onExecCommand: commands.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('container-0'), findsOneWidget);
      await tester.tap(find.byTooltip('Container shell').first);
      await tester.pump();
      expect(commands, ['docker exec -it abcdefabcdef0 sh']);
      await tester.tap(find.byTooltip('Container logs').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text,
        'container log output',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // A single stop acts directly; batch stops wait for each operation result.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Stop').first);
      await tester.pump();
      expect(manager.operations, ['stop:abcdefabcdef0:one']);
      manager.operations.clear();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(manager.operations, hasLength(1));
      expect(find.text('Stop 1/4'), findsOneWidget);
      final client = manager.state.client as _Client;
      for (var i = 0; i < 4; i++) {
        client.results.add(
          DockerOperationResult(
            success: i != 1,
            message: i == 1 ? 'denied' : 'ok',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(manager.operations, hasLength(i == 3 ? 4 : i + 2));
      }
      expect(
        find.textContaining('Batch completed: succeeded 3/4'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await (manager.state.client as _Client).results.close();
      manager.dispose();
    });
  }
}
