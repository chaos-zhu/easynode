import 'package:easynode_native/features/terminal/desktop/terminal_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('clicked links resolve across wrapped lines and CJK prefixes', () {
    final terminal = Terminal()
      ..resize(12, 6)
      ..write('你好 https://example.com/path');
    expect(
      terminalLinkAt(terminal, const CellOffset(4, 1)).toString(),
      'https://example.com/path',
    );
    expect(terminalLinkAt(terminal, const CellOffset(0, 0)), isNull);
  });
  test(
    'matches wrapped logical lines and maps CJK/emoji to terminal cells',
    () {
      final terminal = Terminal()
        ..resize(8, 4)
        ..write('你好😀abcdef');
      final matches = searchTerminal(terminal, '😀abc');
      expect(matches, hasLength(1));
      expect(matches.single.start, const CellOffset(4, 0));
      expect(matches.single.end, const CellOffset(1, 1));
    },
  );
  test('case, word and regex options do not mutate terminal output', () {
    final terminal = Terminal()..write('cat Cat catalog\r\ndog cat');
    expect(searchTerminal(terminal, 'cat'), hasLength(4));
    expect(searchTerminal(terminal, 'cat', caseSensitive: true), hasLength(3));
    expect(searchTerminal(terminal, 'cat', wholeWord: true), hasLength(3));
    expect(searchTerminal(terminal, 'c.t', regex: true), hasLength(4));
    expect(searchTerminal(terminal, '(?=cat)', regex: true), isEmpty);
    expect(
      () => searchTerminal(terminal, '[', regex: true),
      throwsFormatException,
    );
    expect(terminal.buffer.lines[0].getText(), startsWith('cat Cat catalog'));
  });
  test('search caps highlighted matches at 1000', () {
    final terminal = Terminal(maxLines: 2000)
      ..write(List.filled(1200, 'hit\r\n').join());
    expect(searchTerminal(terminal, 'hit'), hasLength(1000));
  });
}
