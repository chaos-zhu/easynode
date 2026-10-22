import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/ui/desktop_select.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = {'a': 'Alpha', 'b': 'Beta', 'c': 'Gamma'};
final _panel = find.byKey(const Key('desktop-select-options'));
Finder _option(String id) =>
    find.descendant(of: _panel, matching: find.byKey(ValueKey(id)));

Future<void> _pump(
  WidgetTester tester, {
  bool multiple = false,
  bool enabled = true,
  bool selectAll = false,
  bool clearable = false,
  bool allowCreate = false,
  int? maxVisibleTags,
  Map<String, String> options = _options,
  List<String> initial = const ['a'],
  Alignment alignment = Alignment.center,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ValueChanged<List<String>>? onChanged,
}) async {
  var selected = [...initial];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [
          brightness == Brightness.dark
              ? AppColorTheme.defaultDark
              : AppColorTheme.defaultLight,
        ],
      ),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            void update(String id, {bool remove = false}) => setState(() {
              selected = multiple
                  ? (remove ? ([...selected]..remove(id)) : [...selected, id])
                  : [id];
              onChanged?.call([...selected]);
            });
            return Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 280,
                  child: DesktopSelect(
                    options: options,
                    descriptions: const {'b': 'SSH key'},
                    values: selected,
                    enabled: enabled,
                    selectAll: selectAll,
                    clearable: clearable,
                    allowCreate: allowCreate,
                    maxVisibleTags: maxVisibleTags,
                    placeholder: 'Choose',
                    onSelected: update,
                    onRemoved: multiple
                        ? (id) => update(id, remove: true)
                        : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(DesktopSelect));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'creatable select filters, deduplicates and keeps collapsed tags editable',
    (tester) async {
      List<String>? result;
      await _pump(
        tester,
        multiple: true,
        allowCreate: true,
        maxVisibleTags: 1,
        clearable: true,
        onChanged: (value) => result = value,
      );
      await _open(tester);
      final query = find.byKey(const Key('desktop-select-create'));
      await tester.enterText(query, 'Delta');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, ['a', 'Delta']);
      expect(find.text('+ 1'), findsOneWidget);
      await tester.enterText(query, 'Alpha');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, ['a', 'Delta']);
      await tester.enterText(query, 'bet');
      await tester.pumpAndSettle();
      expect(_option('a'), findsNothing);
      expect(_option('b'), findsOneWidget);
      await tester.tap(_option('b'));
      await tester.pumpAndSettle();
      expect(result, ['a', 'Delta', 'b']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('+ 2'), findsOneWidget);
      await _open(tester);
      expect(tester.widget<TextField>(query).controller!.text, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-select header tracks partial selection, selects all and clears',
    (tester) async {
      List<String>? result;
      await _pump(
        tester,
        multiple: true,
        selectAll: true,
        clearable: true,
        onChanged: (values) => result = values,
      );
      await _open(tester);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(result, ['a', 'b', 'c']);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      await tester.tap(_option('b'));
      await tester.pumpAndSettle();
      expect(result, ['b']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mouse selection returns the option and closes the anchored panel',
    (tester) async {
      List<String>? result;
      await _pump(tester, onChanged: (values) => result = values);
      final trigger = tester.getRect(find.byType(TextButton));
      await _open(tester);
      final panel = tester.getRect(_panel);
      expect(panel.width, closeTo(trigger.width, .1));
      expect(panel.left, closeTo(trigger.left, .1));
      expect(panel.top, greaterThan(trigger.bottom));
      expect(find.text('SSH key'), findsOneWidget);
      await tester.tap(_option('b'));
      await tester.pumpAndSettle();
      expect(result, ['b']);
      expect(_panel, findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    },
  );

  testWidgets(
    'keyboard arrows select and Escape cancels without changing the value',
    (tester) async {
      List<String>? result;
      await _pump(tester, onChanged: (values) => result = values);
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, ['b']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(result, ['b']);
    },
  );

  testWidgets(
    'ordered multi selection stays open and removable tags do not reopen it',
    (tester) async {
      List<String>? result;
      await _pump(
        tester,
        multiple: true,
        initial: const [],
        onChanged: (values) => result = values,
      );
      await _open(tester);
      await tester.tap(_option('c'));
      await tester.pumpAndSettle();
      await tester.tap(_option('a'));
      await tester.pumpAndSettle();
      expect(result, ['c', 'a']);
      expect(_panel, findsOneWidget);
      await tester.tap(_option('c'));
      await tester.pumpAndSettle();
      expect(result, ['a']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1. Alpha'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      expect(_panel, findsNothing);
    },
  );

  testWidgets(
    'empty panel can be dismissed outside and disabled select cannot open',
    (tester) async {
      await _pump(tester, options: const {}, initial: const []);
      await _open(tester);
      expect(find.text('No options available'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      await _pump(tester, enabled: false);
      await _open(tester);
      expect(_panel, findsNothing);
    },
  );

  testWidgets(
    'long list opens upwards at the bottom and scrolls with enlarged dark text',
    (tester) async {
      List<String>? result;
      await _pump(
        tester,
        alignment: Alignment.bottomRight,
        brightness: Brightness.dark,
        textScale: 1.5,
        options: {for (var i = 0; i < 30; i++) '$i': 'Server $i'},
        initial: const ['0'],
        onChanged: (values) => result = values,
      );
      final trigger = tester.getRect(find.byType(TextButton));
      await _open(tester);
      expect(tester.getRect(_panel).bottom, lessThan(trigger.top));
      await tester.scrollUntilVisible(
        _option('29'),
        200,
        scrollable: find.descendant(
          of: _panel,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(_option('29'));
      await tester.pumpAndSettle();
      expect(result, ['29']);
      expect(tester.takeException(), isNull);
    },
  );
}
