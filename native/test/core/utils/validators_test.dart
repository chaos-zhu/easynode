import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/validators.dart';

void main() {
  test('normalizes server address by trimming and removing trailing slash', () {
    expect(normalizeServerAddress(' http://127.0.0.1:8082/ '), 'http://127.0.0.1:8082');
  });

  test('detects http risk', () {
    expect(isHttpAddress('http://127.0.0.1:8082'), isTrue);
    expect(isHttpAddress('https://example.com'), isFalse);
  });

  test('rejects unsupported scheme', () {
    expect(() => normalizeServerAddress('ftp://example.com'), throwsA(isA<FormatException>()));
  });

  test('rejects address missing host', () {
    expect(() => normalizeServerAddress('http://'), throwsA(isA<FormatException>()));
  });
}
