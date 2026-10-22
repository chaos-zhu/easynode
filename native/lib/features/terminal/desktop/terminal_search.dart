import 'package:xterm/xterm.dart';

class TerminalSearchMatch {
  const TerminalSearchMatch(this.start, this.end);
  final CellOffset start, end;
}

/// Maps UTF-16 match positions to terminal cells, including wide CJK, emoji
/// and wrapped logical lines. Search never writes escape sequences to SSH.
List<TerminalSearchMatch> searchTerminal(
  Terminal terminal,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
  bool regex = false,
}) {
  if (query.isEmpty) return [];
  var pattern = regex ? query : RegExp.escape(query);
  if (wholeWord) pattern = '\\b(?:$pattern)\\b';
  final expression = RegExp(
    pattern,
    caseSensitive: caseSensitive,
    multiLine: true,
    unicode: true,
  );
  final result = <TerminalSearchMatch>[];
  final buffer = terminal.buffer;
  var text = StringBuffer();
  var starts = <CellOffset>[];
  var ends = <CellOffset>[];
  void scan() {
    for (final match in expression.allMatches(text.toString())) {
      if (match.start == match.end || result.length >= 1000) continue;
      result.add(TerminalSearchMatch(starts[match.start], ends[match.end - 1]));
    }
    text = StringBuffer();
    starts = [];
    ends = [];
  }

  for (var y = 0; y < buffer.height; y++) {
    final line = buffer.lines[y];
    if (y > 0 && !line.isWrapped && starts.isNotEmpty) scan();
    for (var x = 0; x < line.getTrimmedLength(); x++) {
      final code = line.getCodePoint(x);
      final width = line.getWidth(x);
      if (width == 0 && code == 0) continue;
      final char = code == 0 ? ' ' : String.fromCharCode(code);
      text.write(char);
      for (var i = 0; i < char.length; i++) {
        starts.add(CellOffset(x, y));
        ends.add(CellOffset(x + (width == 2 ? 2 : 1), y));
      }
    }
  }
  if (starts.isNotEmpty) scan();
  return result;
}

/// Resolve a clicked link across PTY wrapping without changing the selection.
Uri? terminalLinkAt(Terminal terminal, CellOffset cell) {
  final lines = terminal.buffer.lines;
  var start = cell.y, end = cell.y;
  while (start > 0 && lines[start].isWrapped) {
    start--;
  }
  while (end + 1 < lines.length && lines[end + 1].isWrapped) {
    end++;
  }
  var offset = 0;
  final text = StringBuffer();
  for (var y = start; y <= end; y++) {
    final line = lines[y];
    if (y < cell.y) offset += line.getText(0, line.getTrimmedLength()).length;
    if (y == cell.y) offset += line.getText(0, cell.x).length;
    text.write(line.getText(0, line.getTrimmedLength()));
  }
  for (final match in RegExp(
    r'(?:https?://|www\.)[^\s<>]+',
  ).allMatches(text.toString())) {
    if (offset >= match.start && offset < match.end) {
      final raw = match.group(0)!;
      return Uri.tryParse(raw.startsWith('www.') ? 'https://$raw' : raw);
    }
  }
  return null;
}
