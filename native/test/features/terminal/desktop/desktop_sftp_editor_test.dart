import 'dart:convert';

import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_sftp_editor.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_text_codec.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

class _Manager extends SftpSessionManager {
  _Manager(this.bytes);
  Uint8List bytes;
  int reads = 0;
  Uint8List? saved;
  bool failSave = false;
  @override
  Future<Uint8List> readTextFile(
    String path, {
    int maxBytes = SftpSessionManager.defaultTextFileMaxBytes,
  }) async {
    reads++;
    return bytes;
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    if (failSave) throw StateError('write denied');
    saved = bytes;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _Manager manager) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(DesktopTextCodec.load);
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
          theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DesktopSftpEditor(
                    manager: manager,
                    remotePath: '/root/config.yaml',
                    fileName: 'config.yaml',
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.text('Open editor'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(
      find.byType(CodeEditor),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((e) => e.data)
          .join(' | '),
    );
  }

  CodeLineEditingController code(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
  testWidgets(
    'desktop editor preserves UTF8 BOM and CRLF when saving and resets safely',
    (tester) async {
      final manager = _Manager(
        Uint8List.fromList([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('hello\r\nworld\r\n'),
        ]),
      );
      await mount(tester, manager);
      expect(code(tester).text, 'hello\nworld\n');
      code(tester).text = 'changed\nworld\n';
      await tester.pump();
      await tester.tap(find.text('Reset'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(code(tester).text, 'hello\nworld\n');
      code(tester).text = 'saved\n';
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(manager.saved, [0xef, 0xbb, 0xbf, ...utf8.encode('saved\r\n')]);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(CodeEditor), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
      manager.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'GB18030 is detected and dirty close keeps editor open on failed save',
    (tester) async {
      final codec = await tester.runAsync(DesktopTextCodec.load);
      final manager = _Manager(codec!.encode('中文\r下一行', 'gb18030'))
        ..failSave = true;
      await mount(tester, manager);
      expect(code(tester).text, '中文\n下一行');
      code(tester).text = '中文😀\n';
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Save and close'), findsOneWidget);
      await tester.tap(find.text('Save and close'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byType(CodeEditor), findsOneWidget);
      expect(find.textContaining('write denied'), findsOneWidget);
      manager.failSave = false;
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(codec.decode(manager.saved!, 'gb18030'), '中文😀\r');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
      manager.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'encoding changes require discarding edits and update the live editor',
    (tester) async {
      final manager = _Manager(Uint8List.fromList(utf8.encode('original\n')));
      await mount(tester, manager);
      code(tester).text = 'unsaved';
      await tester.pump();
      await tester.tap(find.text('Auto detect (UTF-8)'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('GB18030'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Reload encoding'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(code(tester).text, 'unsaved');
      expect(manager.reads, 1);
      manager.bytes = Uint8List.fromList(utf8.encode('refreshed on server\n'));
      await tester.tap(find.text('Auto detect (UTF-8)'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('GB18030'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(code(tester).text, 'refreshed on server\n');
      expect(manager.reads, 2);
      code(tester).text = 'new';
      await tester.pump();
      expect(find.textContaining('[Modified]'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
      manager.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
