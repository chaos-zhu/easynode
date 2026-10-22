import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/terminal/desktop/terminal_output_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> rule({
  String scope = 'match',
  int priority = 10,
  String token = 'red',
  String pattern = 'ERROR',
}) => {
  'id': 'rule-$token',
  'enabled': true,
  'pattern': pattern,
  'flags': 'g',
  'scope': scope,
  'priority': priority,
  'style': {
    'foreground': {'source': 'theme', 'token': token},
  },
};
void main() {
  TerminalOutputHighlighter create(List<Map<String, dynamic>> rules) {
    final settings = DesktopTerminalSettings.defaults();
    settings.highlighting['enabled'] = true;
    return TerminalOutputHighlighter()..configure(settings, rules);
  }

  test('semantic style restores remote truecolor and text unchanged', () {
    final highlighter = create([rule()]);
    final output = highlighter.process('\x1b[38;2;10;20;30mERROR tail');
    expect(
      output,
      '\x1b[38;2;10;20;30m\x1b[31mERROR\x1b[0m\x1b[38;2;10;20;30m tail',
    );
  });
  test('incomplete ANSI and OSC carry into next packet without corruption', () {
    final highlighter = create([]);
    expect(highlighter.process('a\x1b[38;2;'), 'a');
    expect(highlighter.process('1;2;3mb'), '\x1b[38;2;1;2;3mb');
    expect(highlighter.process('\x1b]0;title'), '');
    expect(highlighter.process('\x07text'), '\x1b]0;title\x07text');
  });
  test('priority resolves overlap and line-tail preserves line terminator', () {
    final highlighter = create([
      rule(priority: 1),
      rule(priority: 20, token: 'green'),
    ]);
    expect(highlighter.process('ERROR'), '\x1b[32mERROR\x1b[0m');
    final tail = create([rule(scope: 'lineTail')]);
    expect(
      tail.process('a ERROR tail\r\nnext'),
      'a \x1b[31mERROR tail\x1b[0m\r\nnext',
    );
    final line = create([rule(scope: 'line')]);
    expect(line.process('x ERROR\r\nnext'), '\x1b[31mx ERROR\x1b[0m\r\nnext');
  });
  test(
    'disabled highlighting preserves control sequences and reset clears state',
    () {
      final highlighter = TerminalOutputHighlighter();
      expect(highlighter.process('\x1b[31mraw\r\n'), '\x1b[31mraw\r\n');
      highlighter.process('\x1b[');
      highlighter.reset();
      expect(highlighter.process('plain'), 'plain');
    },
  );
}
