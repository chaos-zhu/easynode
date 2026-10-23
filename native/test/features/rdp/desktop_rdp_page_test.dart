import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/features/rdp/desktop_rdp_page.dart';
import 'package:easynode_native/features/rdp/desktop_rdp_workspace.dart';
import 'package:easynode_native/features/rdp/rdp_engine.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:easynode_native/state/desktop_server_catalog_provider.dart';
import 'package:easynode_native/state/plus_info_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Workspace extends DesktopRdpWorkspace {
  _Workspace() : super(fetch: (_) => throw UnimplementedError());
  final entries = <DesktopRdpConnection>[];
  final opens = <String>[];
  @override
  List<DesktopRdpConnection> get connections => entries;
  @override
  Future<void> open(
    ServerModel server, {
    RdpOptions options = const RdpOptions(),
  }) async {
    opens.add(server.id);
    if (!entries.any((e) => e.server.id == server.id)) {
      entries.add(
        DesktopRdpConnection(server, options)
          ..status = RdpWindowStatus.connected,
      );
      notifyListeners();
    }
  }

  @override
  Future<void> close(DesktopRdpConnection entry) async {
    entries.remove(entry);
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'RDP menu filters hosts and cards focus/close at minimum desktop content width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(706, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final workspace = _Workspace();
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopRdpWorkspaceProvider.overrideWithValue(workspace),
            isPlusActiveProvider.overrideWithValue(true),
            desktopServerCatalogProvider.overrideWith(
              (ref) async => HostCatalog.fromJson({
                'hosts': [
                  {
                    'id': 'rdp',
                    'name': 'Windows',
                    'connectType': 'rdp',
                    'isConfig': true,
                  },
                  {
                    'id': 'ssh',
                    'name': 'Linux',
                    'connectType': 'ssh',
                    'isConfig': true,
                  },
                  {
                    'id': 'missing',
                    'name': 'Unconfigured',
                    'connectType': 'rdp',
                    'isConfig': false,
                  },
                ],
              }),
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const Scaffold(body: DesktopRdpPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(workspace.opens, isEmpty);
      expect(find.text('Adaptive resolution'), findsNothing);
      await tester.tap(find.text('Connection settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adaptive resolution'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1920 × 1080'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium quality'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High quality'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New connection'));
      await tester.pumpAndSettle();
      expect(find.text('Linux'), findsNothing);
      expect(find.text('Unconfigured'), findsNothing);
      await tester.tap(find.text('Windows'));
      await tester.pumpAndSettle();
      expect(workspace.opens, ['rdp']);
      expect(workspace.entries.single.options.resolution, '1920x1080');
      expect(workspace.entries.single.options.quality, RdpQuality.high);
      expect(workspace.entries.single.options.clipboard, isFalse);
      expect(find.text('Connected'), findsOneWidget);
      await tester.tap(find.text('Windows'));
      await tester.pumpAndSettle();
      expect(workspace.opens, ['rdp', 'rdp']);
      await tester.tap(find.byTooltip('Close connection'));
      await tester.pumpAndSettle();
      expect(find.text('No remote desktop connections'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
