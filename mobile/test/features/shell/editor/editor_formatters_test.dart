import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_formatters.dart';

void main() {
  group('formatJson', () {
    test('pretty-prints with 2-space indent', () {
      final out = formatJson('{"a":1,"b":[1,2,3]}');
      expect(out, contains('\n  "a": 1'));
      expect(out, contains('    1'));
    });

    test('throws FormatException on invalid JSON', () {
      expect(() => formatJson('{not json'), throwsA(isA<FormatException>()));
    });
  });

  group('formatYaml', () {
    test('round-trips a simple map with 2-space indent', () {
      final out = formatYaml('foo: 1\nbar:\n  baz: hello');
      expect(out, contains('foo: 1'));
      expect(out, contains('bar:'));
      expect(out, contains('  baz: hello'));
    });

    test('throws FormatException on invalid YAML', () {
      expect(() => formatYaml(': : : not yaml'), throwsA(isA<FormatException>()));
    });
  });

  group('formatXml', () {
    test('pretty-prints valid xml with 2-space indent', () {
      final out = formatXml('<a><b>x</b></a>');
      expect(out, contains('<a>'));
      expect(out, contains('  <b>x</b>'));
    });

    test('throws FormatException on invalid XML', () {
      expect(() => formatXml('<a><b></a>'), throwsA(isA<FormatException>()));
    });
  });
}
