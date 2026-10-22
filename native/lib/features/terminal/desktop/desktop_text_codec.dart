import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// GB18030's two-byte mapping and linear four-byte ranges. No OS process,
/// platform plugin, or server conversion is involved in editing remote files.
class DesktopTextCodec {
  DesktopTextCodec._(this._pairs, this._ranges);
  final List<int> _pairs;
  final List<List<int>> _ranges;
  late final Map<int, int> _reverse = {
    for (var i = 0; i < _pairs.length; i++) _pairs[i]: i,
  };
  static Future<DesktopTextCodec>? _loaded;
  static Future<DesktopTextCodec> load() => _loaded ??= _load();
  static Future<DesktopTextCodec> _load() async {
    final data = await rootBundle.load('assets/terminal/gb18030.json.gz');
    return fromCompressed(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static DesktopTextCodec fromCompressed(List<int> bytes) {
    final table = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
    return DesktopTextCodec._(
      (table['pairs'] as List).cast<int>(),
      (table['ranges'] as List).map((r) => (r as List).cast<int>()).toList(),
    );
  }

  String decode(List<int> bytes, String encoding) {
    if (encoding == 'utf8') return utf8.decode(bytes);
    final output = <int>[];
    for (var i = 0; i < bytes.length;) {
      final a = bytes[i++];
      if (a < 0x80) {
        output.add(a);
        continue;
      }
      if (a < 0x81 || a > 0xfe || i == bytes.length) {
        throw const FormatException('Invalid GB18030 sequence');
      }
      final b = bytes[i++];
      if (b >= 0x30 && b <= 0x39) {
        if (i + 1 >= bytes.length) {
          throw const FormatException('Truncated GB18030 sequence');
        }
        final c = bytes[i++], d = bytes[i++];
        if (c < 0x81 || c > 0xfe || d < 0x30 || d > 0x39) {
          throw const FormatException('Invalid GB18030 sequence');
        }
        final pointer =
            (((a - 0x81) * 10 + b - 0x30) * 126 + c - 0x81) * 10 + d - 0x30;
        final range = _ranges
            .where((r) => pointer >= r[0] && pointer <= r[2])
            .firstOrNull;
        if (range == null) {
          throw const FormatException('Unmapped GB18030 sequence');
        }
        output.add(range[1] + pointer - range[0]);
      } else {
        final column = b >= 0x40 && b <= 0x7e
            ? b - 0x40
            : b >= 0x80 && b <= 0xfe
            ? b - 0x41
            : -1;
        if (column < 0) throw const FormatException('Invalid GB18030 sequence');
        output.add(_pairs[(a - 0x81) * 190 + column]);
      }
    }
    return String.fromCharCodes(output);
  }

  Uint8List encode(String text, String encoding) {
    if (encoding == 'utf8') return Uint8List.fromList(utf8.encode(text));
    final output = <int>[];
    for (final cp in text.runes) {
      if (cp < 0x80) {
        output.add(cp);
        continue;
      }
      final index = _reverse[cp];
      if (index != null) {
        final column = index % 190;
        output.addAll([
          index ~/ 190 + 0x81,
          column + (column < 63 ? 0x40 : 0x41),
        ]);
        continue;
      }
      final range = _ranges
          .where((r) => cp >= r[1] && cp <= r[1] + r[2] - r[0])
          .firstOrNull;
      if (range == null) {
        throw const FormatException('Unmapped GB18030 character');
      }
      var p = range[0] + cp - range[1];
      final d = p % 10 + 0x30;
      p ~/= 10;
      final c = p % 126 + 0x81;
      p ~/= 126;
      final b = p % 10 + 0x30;
      p ~/= 10;
      output.addAll([p + 0x81, b, c, d]);
    }
    return Uint8List.fromList(output);
  }
}

String detectTextEol(String text) => text.contains('\r\n')
    ? 'CRLF'
    : text.contains('\r')
    ? 'CR'
    : 'LF';
String normalizeTextEol(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
String applyTextEol(String text, String eol) =>
    normalizeTextEol(text).replaceAll('\n', switch (eol) {
      'CRLF' => '\r\n',
      'CR' => '\r',
      _ => '\n',
    });
