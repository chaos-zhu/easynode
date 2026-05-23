import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_language.dart';

void main() {
  group('detectFromFileName', () {
    test('maps .json to JSON with formatter and highlight', () {
      final lang = detectFromFileName('config.json');
      expect(lang.id, 'JSON');
      expect(lang.formatSupported, isTrue);
      expect(lang.highlightMode, isNotNull);
      expect(lang.defaultIndent, 2);
    });

    test('maps .yaml and .yml to YAML', () {
      expect(detectFromFileName('a.yaml').id, 'YAML');
      expect(detectFromFileName('a.yml').id, 'YAML');
      expect(detectFromFileName('a.yaml').formatSupported, isTrue);
    });

    test('maps .xml to XML', () {
      final lang = detectFromFileName('pom.xml');
      expect(lang.id, 'XML');
      expect(lang.formatSupported, isTrue);
    });

    test('maps .ts to TypeScript without formatter support', () {
      final lang = detectFromFileName('app.ts');
      expect(lang.id, 'TypeScript');
      expect(lang.formatSupported, isFalse);
      expect(lang.highlightMode, isNotNull);
    });

    test('maps .sh to Bash without formatter support', () {
      final lang = detectFromFileName('deploy.sh');
      expect(lang.id, 'Bash');
      expect(lang.formatSupported, isFalse);
    });

    test('unknown extension falls back to plaintext with no highlight', () {
      final lang = detectFromFileName('notes.unknownext');
      expect(lang.id, 'Plain Text');
      expect(lang.formatSupported, isFalse);
      expect(lang.highlightMode, isNull);
    });

    test('file without extension falls back to plaintext', () {
      final lang = detectFromFileName('README');
      expect(lang.id, 'Plain Text');
      expect(lang.highlightMode, isNull);
    });

    test('is case-insensitive on extension', () {
      expect(detectFromFileName('UPPER.JSON').id, 'JSON');
    });
  });
}
