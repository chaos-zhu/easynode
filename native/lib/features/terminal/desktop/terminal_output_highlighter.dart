import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_terminal_settings.dart';

/// Stream decorator: remote ANSI sequences remain in order and their SGR
/// state is restored after each semantic highlight (including truecolor).
class TerminalOutputHighlighter {
  bool enabled = false;
  bool debugMode = false;
  List<_Rule> _rules = [];
  final _sgr = <String, String>{};
  String _carry = '';
  static final _ansi = RegExp(
    r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[PX^_][\s\S]*?\x1b\\|\x1b(?![\[\]PX^_])[ -/]*[0-~]',
  );
  static const tokens = [
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
    'brightBlack',
    'brightRed',
    'brightGreen',
    'brightYellow',
    'brightBlue',
    'brightMagenta',
    'brightCyan',
    'brightWhite',
  ];

  void configure(
    DesktopTerminalSettings settings,
    List<Map<String, dynamic>> builtins,
  ) {
    enabled = settings.highlighting['enabled'] == true;
    debugMode = settings.highlighting['debugMode'] == true;
    final overrides = {
      for (final raw in settings.highlighting['builtinOverrides'] as List)
        terminalMap(raw)['id']: terminalMap(raw),
    };
    final rules = [
      ...builtins.map((rule) => overrides[rule['id']] ?? rule),
      ...(settings.highlighting['customRules'] as List).map(terminalMap),
    ];
    _rules = [];
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (rule['enabled'] == false ||
          (rule['pattern']?.toString().length ?? 0) > 4096) {
        continue;
      }
      try {
        final flags = rule['flags']?.toString() ?? '';
        _rules.add(
          _Rule(
            rule,
            i,
            RegExp(
              rule['pattern'] as String,
              caseSensitive: !flags.contains('i'),
              multiLine: flags.contains('m'),
              unicode: flags.contains('u'),
            ),
          ),
        );
      } on FormatException {
        /* Invalid server rules do not break shell output. */
      }
    }
  }

  void reset() {
    _carry = '';
    _sgr.clear();
  }

  String process(String data) {
    var text = _carry + data;
    _carry = '';
    var scan = 0;
    while (scan < text.length) {
      final escape = text.indexOf('\x1b', scan);
      if (escape < 0) break;
      final sequence = _ansi.matchAsPrefix(text, escape);
      if (sequence != null) {
        scan = sequence.end;
        continue;
      }
      final tail = text.substring(escape);
      if (RegExp(r'^\x1b[ -/]*$').hasMatch(tail) ||
          tail.startsWith('\x1b[') ||
          tail.startsWith('\x1b]') ||
          RegExp(r'^\x1b[PX^_]').hasMatch(tail)) {
        _carry = tail;
        text = text.substring(0, escape);
        break;
      }
      scan = escape + 1;
    }
    final plain = text.replaceAll(_ansi, '');
    final matches = <_Hit>[];
    if (enabled && text.length <= 65536) {
      final candidates = <_Hit>[];
      for (final rule in _rules) {
        for (final match in rule.expression.allMatches(plain)) {
          if (match.start == match.end || candidates.length >= 2000) break;
          var start = match.start, end = match.end;
          final scope = rule.json['scope'];
          if (scope == 'line' || scope == 'lineTail') {
            if (scope == 'line') {
              start =
                  (match.start == 0
                      ? -1
                      : plain.lastIndexOf('\n', match.start - 1)) +
                  1;
            }
            final newline = plain.indexOf('\n', end);
            end = newline < 0 ? plain.length : newline;
            if (end > start && plain[end - 1] == '\r') end--;
          }
          candidates.add(_Hit(start, end, rule));
        }
      }
      candidates.sort((a, b) {
        final priority = ((b.rule.json['priority'] as num?) ?? 0).compareTo(
          (a.rule.json['priority'] as num?) ?? 0,
        );
        return priority != 0 ? priority : a.rule.index.compareTo(b.rule.index);
      });
      for (final hit in candidates) {
        if (!matches.any((m) => hit.start < m.end && m.start < hit.end)) {
          matches.add(hit);
        }
      }
      matches.sort((a, b) => a.start.compareTo(b.start));
    }
    if (debugMode && matches.isNotEmpty) {
      debugPrint(
        'Terminal highlight: ${matches.map((hit) => hit.rule.json['id']).join(', ')}',
      );
    }
    final result = StringBuffer();
    var position = 0, matchIndex = 0;
    _Hit? active;
    void restore() {
      result.write('\x1b[0m');
      if (_sgr.isNotEmpty) result.write('\x1b[${_sgr.values.join(';')}m');
    }

    void sync() {
      if (active != null && position >= active!.end) {
        restore();
        active = null;
        matchIndex++;
      }
      if (active == null &&
          matchIndex < matches.length &&
          position == matches[matchIndex].start) {
        active = matches[matchIndex];
        result.write(_style(terminalMap(active!.rule.json['style'])));
      }
    }

    var offset = 0;
    while (offset < text.length) {
      final escape = _ansi.matchAsPrefix(text, offset);
      if (escape != null) {
        final sequence = escape.group(0)!;
        _track(sequence);
        result.write(sequence);
        if (active != null && sequence.endsWith('m')) {
          result.write(_style(terminalMap(active!.rule.json['style'])));
        }
        offset = escape.end;
      } else {
        sync();
        result.write(text[offset]);
        offset++;
        position++;
      }
    }
    if (active != null) restore();
    return result.toString();
  }

  String _style(Map<String, dynamic> style) =>
      '${_color(style['foreground'], false)}${_color(style['background'], true)}'
      '${style['bold'] == true ? '\x1b[1m' : ''}${style['italic'] == true ? '\x1b[3m' : ''}${style['underline'] == true ? '\x1b[4m' : ''}';
  String _color(Object? raw, bool background) {
    final color = terminalMap(raw);
    if (color.isEmpty) return '';
    if (color['source'] == 'theme') {
      final index = tokens.indexOf(color['token']?.toString() ?? '');
      if (index < 0) return '';
      return '\x1b[${(index < 8 ? 30 + index : 90 + index - 8) + (background ? 10 : 0)}m';
    }
    final c = terminalColor(color['value']);
    return '\x1b[${background ? 48 : 38};2;${(c.r * 255).round()};${(c.g * 255).round()};${(c.b * 255).round()}m';
  }

  void _track(String sequence) {
    final match = RegExp(r'^\x1b\[([0-9:;]*)m$').firstMatch(sequence);
    if (match == null) return;
    final parts = match[1]!.isEmpty ? ['0'] : match[1]!.split(';');
    for (var i = 0; i < parts.length; i++) {
      final code = int.tryParse(parts[i].split(':').first) ?? 0;
      final value = parts[i];
      if (code == 0) {
        _sgr.clear();
        continue;
      }
      const starts = {
        1: 'bold',
        2: 'dim',
        3: 'italic',
        4: 'underline',
        5: 'blink',
        6: 'blink',
        7: 'inverse',
        8: 'hidden',
        9: 'strike',
        20: 'italic',
        21: 'underline',
      };
      const ends = {
        22: 'bold',
        23: 'italic',
        24: 'underline',
        25: 'blink',
        27: 'inverse',
        28: 'hidden',
        29: 'strike',
        39: 'foreground',
        49: 'background',
        59: 'underlineColor',
      };
      if (starts.containsKey(code)) {
        _sgr[starts[code]!] = value;
      } else if (ends.containsKey(code)) {
        _sgr.remove(ends[code]);
        if (code == 22) _sgr.remove('dim');
      } else if (code >= 30 && code <= 37 || code >= 90 && code <= 97) {
        _sgr['foreground'] = value;
      } else if (code >= 40 && code <= 47 || code >= 100 && code <= 107) {
        _sgr['background'] = value;
      } else if (code == 38 || code == 48 || code == 58) {
        final key = code == 38
            ? 'foreground'
            : code == 48
            ? 'background'
            : 'underlineColor';
        var end = i;
        if (!value.contains(':') && i + 1 < parts.length) {
          end =
              (i +
                      (parts[i + 1] == '2'
                          ? 4
                          : parts[i + 1] == '5'
                          ? 2
                          : 0))
                  .clamp(i, parts.length - 1);
        }
        _sgr[key] = parts.sublist(i, end + 1).join(';');
        i = end;
      }
    }
  }
}

class _Rule {
  _Rule(this.json, this.index, this.expression);
  final Map<String, dynamic> json;
  final int index;
  final RegExp expression;
}

class _Hit {
  _Hit(this.start, this.end, this.rule);
  final int start, end;
  final _Rule rule;
}
