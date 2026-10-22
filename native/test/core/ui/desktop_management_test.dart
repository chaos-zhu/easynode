import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/ui/desktop_management.dart';
import 'package:easynode_native/core/ui/desktop_select.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'fixed actions stay visible and clickable through horizontal and vertical scrolling',
    (tester) async {
      var edited = -1;
      var opened = -1;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 520,
            height: 320,
            child: ManagementTable(
              columns: const [
                ManagementColumn('Name', width: 260),
                ManagementColumn('Description', width: 300),
                ManagementColumn.actions('Actions', width: 200),
              ],
              onRowTap: (index) => opened = index,
              rows: [
                for (var i = 0; i < 12; i++)
                  [
                    Text('Instance $i'),
                    Text(
                      i == 0
                          ? 'A long description that wraps over several lines to check row alignment.'
                          : 'Description $i',
                    ),
                    Row(
                      children: [
                        ManagementLink(
                          key: ValueKey('edit-$i'),
                          label: 'Edit',
                          onPressed: () => edited = i,
                        ),
                        ManagementLink(label: 'Delete', onPressed: () {}),
                      ],
                    ),
                  ],
              ],
              expanded: const {
                0: SizedBox(height: 80, child: Text('Expanded output')),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('edit-0'));
      final initialPosition = tester.getCenter(edit);
      expect(
        tester.getRect(find.byType(ManagementTable)).contains(initialPosition),
        isTrue,
      );
      await tester.tap(edit);
      expect(edited, 0);
      expect(opened, -1);
      final horizontal = find.byType(SingleChildScrollView);
      await tester.drag(horizontal, const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(edit).dx, closeTo(initialPosition.dx, .01));
      await tester.tap(edit);
      expect(edited, 0);
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      final third = find.byKey(const ValueKey('edit-3'));
      await tester.ensureVisible(third);
      await tester.tap(third);
      expect(edited, 3);
      await tester.tap(find.text('Description 3'));
      expect(opened, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Web pager selects numbered pages and resets after changing page size',
    (tester) async {
      var page = 1;
      var size = 20;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 680,
            child: StatefulBuilder(
              builder: (context, setState) => ManagementPagination(
                total: 2000,
                page: page,
                pageSize: size,
                onPage: (v) => setState(() => page = v),
                onPageSize: (v) => setState(() {
                  size = v;
                  page = 1;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('2000 total')).dx, greaterThan(150));
      await tester.tap(find.byTooltip('Page 5'));
      await tester.pumpAndSettle();
      expect(page, 5);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(page, 6);
      await tester.tap(find.byTooltip('Page 100'));
      await tester.pumpAndSettle();
      expect(page, 100);
      await tester.tap(find.byType(DesktopSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50 / page'));
      await tester.pumpAndSettle();
      expect(size, 50);
      expect(page, 1);
      expect(find.byTooltip('Page 40'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
