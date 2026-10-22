import 'dart:io';

import 'package:easynode_native/features/terminal/desktop/desktop_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final codec = DesktopTextCodec.fromCompressed(
    File('assets/terminal/gb18030.json.gz').readAsBytesSync(),
  );
  test(
    'GB18030 decodes GBK and four-byte characters without changing bytes',
    () {
      // Python GB18030 reference: 中文 € 😀 𠀀
      final bytes = [
        0xd6,
        0xd0,
        0xce,
        0xc4,
        0x20,
        0xa2,
        0xe3,
        0x20,
        0x94,
        0x39,
        0xfc,
        0x36,
        0x20,
        0x95,
        0x32,
        0x82,
        0x36,
      ];
      expect(codec.decode(bytes, 'gb18030'), '中文 € 😀 𠀀');
      expect(codec.encode('中文 € 😀 𠀀', 'gb18030'), bytes);
      expect(
        codec.decode(codec.encode('Hello\n测试\r\n', 'utf8'), 'utf8'),
        'Hello\n测试\r\n',
      );
    },
  );
  test('GB18030 covers two-byte boundaries and Unicode range transitions', () {
    final text = String.fromCharCodes([
      0x80,
      0xa5,
      0x20ac,
      0xd7ff,
      0xe000,
      0xffff,
      0x10000,
      0x10ffff,
    ]);
    expect(codec.decode(codec.encode(text, 'gb18030'), 'gb18030'), text);
    for (final invalid in [
      [0xff],
      [0x81],
      [0x81, 0x30],
      [0x81, 0x30, 0x81, 0x2f],
      [0xfe, 0x39, 0xfe, 0x39],
    ]) {
      expect(() => codec.decode(invalid, 'gb18030'), throwsFormatException);
    }
    expect(() => codec.decode([0xff], 'utf8'), throwsFormatException);
  });
  test(
    'line endings preserve CRLF and CR with a normalized editing buffer',
    () {
      expect(detectTextEol('a\r\nb\r\n'), 'CRLF');
      expect(detectTextEol('a\rb\r'), 'CR');
      expect(detectTextEol('a\nb'), 'LF');
      expect(normalizeTextEol('a\r\nb\rc\n'), 'a\nb\nc\n');
      expect(applyTextEol('a\nb\n', 'CRLF'), 'a\r\nb\r\n');
      expect(applyTextEol('a\r\nb\n', 'CR'), 'a\rb\r');
    },
  );
}
