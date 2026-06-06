import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_text_sniffer.dart';

void main() {
  group('sniffAndDecode', () {
    test('returns plain text for ASCII bytes', () {
      final result = sniffAndDecode(Uint8List.fromList(utf8.encode('hello\nworld')));
      expect(result.malformedUtf8, isFalse);
      expect(result.text, 'hello\nworld');
    });

    test('handles valid multibyte UTF-8 without flagging malformed', () {
      final result = sniffAndDecode(Uint8List.fromList(utf8.encode('你好 hello 🌐')));
      expect(result.malformedUtf8, isFalse);
      expect(result.text, '你好 hello 🌐');
    });

    test('flags malformedUtf8 but still decodes via allowMalformed', () {
      final bytes = Uint8List.fromList([0x68, 0xC3, 0x28, 0x69]); // invalid UTF-8
      final result = sniffAndDecode(bytes);
      expect(result.malformedUtf8, isTrue);
      expect(result.text, isNotEmpty);
    });

    test('empty input is treated as plain text', () {
      final result = sniffAndDecode(Uint8List(0));
      expect(result.malformedUtf8, isFalse);
      expect(result.text, '');
    });
  });
}
