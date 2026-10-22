import 'dart:convert';

import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v3 settings retain HTML definitions while changing supported appearance',
    () {
      final document = DesktopTerminalSettings.defaults().json;
      document['appearance']['customHtmlThemes'] = [
        {
          'id': 'custom-html:one',
          'name': 'Web',
          'html': '<canvas></canvas>',
          'css': 'body{}',
        },
      ];
      document['appearance']['background']['mode'] = 'html';
      document['appearance']['background']['htmlThemeId'] = 'custom-html:one';
      final settings = DesktopTerminalSettings.fromJson(document);
      final copy = settings.copy();
      copy.font['size'] = 18;
      expect(
        copy.appearance['customHtmlThemes'],
        document['appearance']['customHtmlThemes'],
      );
      expect(copy.background['htmlThemeId'], 'custom-html:one');
      expect(settings.fontSize, 16);
      expect(copy.fontSize, 18);
      expect(copy.json['version'], 3);
    },
  );
  test('CSS colors map RGBA alpha and RGB percentages correctly', () {
    expect(terminalColor('#abc'), const Color(0xffaabbcc));
    expect(terminalColor('#aabbcc80'), const Color(0x80aabbcc));
    expect(terminalColor('rgb(100%, 0%, 0%)'), const Color(0xffff0000));
    expect(terminalColor('rgba(1, 2, 3, 0.5)').a, closeTo(.5, .01));
    expect(terminalColor('invalid', Colors.blue), Colors.blue);
  });
  test(
    'bundled palette and custom overrides resolve without web renderer',
    () async {
      final themes = terminalMap(
        jsonDecode(await rootBundle.loadString('assets/terminal/themes.json')),
      );
      expect(themes.keys, contains('Cobalt_Neon'));
      final settings = DesktopTerminalSettings.defaults();
      settings.overrides['foreground'] = '#112233';
      expect(
        desktopTerminalTheme(settings, themes).foreground,
        const Color(0xff112233),
      );
      expect(
        desktopTerminalTheme(settings, themes, transparent: true).background,
        Colors.transparent,
      );
      settings.appearance['activeThemeId'] = 'custom:one';
      settings.appearance['customThemes'] = [
        {
          'id': 'custom:one',
          'name': 'One',
          'colors': {'background': '#123456'},
        },
      ];
      expect(
        desktopTerminalTheme(settings, themes).background,
        const Color(0xff123456),
      );
    },
  );
  test(
    'invalid local preferences recover to defaults; writes retain unrelated preferences',
    () async {
      var saved = '';
      final prefs = DesktopTerminalPreferences((value) async {
        saved = value;
      }, 'not json');
      expect(prefs.state, isEmpty);
      await prefs.set('sftpColumns', ['size']);
      await prefs.set('grid', true);
      expect(jsonDecode(saved), {
        'sftpColumns': ['size'],
        'grid': true,
      });
      prefs.dispose();
    },
  );
}
