import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_sftp_panel.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'desktop_test_support.dart';

SftpFileEntry entry(String name, {bool directory = false, bool link = false}) =>
    SftpFileEntry(
      name: name,
      type: link
          ? 'l'
          : directory
          ? 'd'
          : '-',
      size: 128,
      modifyTime: DateTime(2026, 1, 1),
      permissions: '-rw-r--r--',
      ownerName: 'root',
      groupName: 'root',
    );

class _Manager extends SftpSessionManager {
  final state = SftpSessionState(server: host('one'))
    ..status = SftpConnectionStatus.connected;
  final opened = <String>[], created = <String>[];
  @override
  SftpSessionState? get activeSession => state;
  @override
  SftpSessionState? sessionFor(String id) => state;
  @override
  bool isConnected(String hostId) => true;
  @override
  void activate(String hostId) {}
  @override
  Future<bool> isRemoteDirectory(String path) async =>
      path.endsWith('linked-folder');
  @override
  Future<void> openPath(String path, {bool showLoading = true}) async {
    opened.add(path);
    state.update(currentPath: path);
  }

  @override
  Future<void> createDirectory(String name) async {
    created.add(name);
    state.update(entries: [...state.entries, entry(name, directory: true)]);
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
    'desktop SFTP fits narrow pane, selects files and provides context actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(450, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final manager = _Manager();
      manager.state.update(
        entries: [
          entry('folder', directory: true),
          entry('notes.txt'),
          entry('linked-folder', link: true),
        ],
      );
      final request = ValueNotifier<String?>('/srv');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
              body: DesktopSftpPanel(
                server: manager.state.server,
                manager: manager,
                pathRequest: request,
                onExecCommand: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(manager.opened, ['/srv']);
      expect(find.text('notes.txt'), findsOneWidget);
      final fileRect = tester.getRect(find.text('notes.txt'));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      manager.state.update(loadingDirectory: true);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.getRect(find.text('notes.txt')), fileRect);
      manager.state.update(loadingDirectory: false);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.getRect(find.text('notes.txt')), fileRect);
      expect(find.text('Favorites'), findsNothing);
      expect(find.byTooltip('Transfers'), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('Reconnect')).dx,
        greaterThan(400),
      );
      await tester.tap(find.byTooltip('Search files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pump();
      expect(find.text('folder'), findsNothing);
      expect(find.text('notes.txt'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tapAt(const Offset(440, 590));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('folder'), findsOneWidget);
      await tester.tap(find.text('notes.txt'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(manager.state.selectedNames, {'notes.txt'});
      await tester.tap(find.text('notes.txt'), buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Copy to…'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tapAt(const Offset(440, 590));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('linked-folder'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('linked-folder'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(manager.opened.last, '/srv/linked-folder');
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '/opt');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(manager.opened.last, '/opt');
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '/not-submitted');
      await tester.tap(find.text('Upload'));
      await tester.pump();
      expect(manager.opened.last, '/opt');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
      request.dispose();
    },
  );
  testWidgets('new folder uses validated desktop prompt with Enter submit', (
    tester,
  ) async {
    final manager = _Manager();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
            body: DesktopSftpPanel(
              server: manager.state.server,
              manager: manager,
              onExecCommand: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New folder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField), 'new-folder');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(manager.created, ['new-folder']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
  });
}
