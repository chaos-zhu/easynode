import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/core/crypto/aes_gcm_crypto.dart';
import 'package:pointycastle/export.dart';

Uint8List _encryptForTest(Uint8List key, Uint8List iv, Uint8List plaintext) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(plaintext);
}

void main() {
  test('decrypts AES-256-GCM envelope produced by Node native crypto layout', () {
    final key = Uint8List.fromList(utf8.encode('0123456789abcdef0123456789abcdef'));
    final iv = Uint8List.fromList(List<int>.generate(12, (i) => i));
    final plaintext = Uint8List.fromList(utf8.encode('{"host":"127.0.0.1","port":22}'));
    final encrypted = _encryptForTest(key, iv, plaintext);
    final tag = encrypted.sublist(encrypted.length - 16);
    final ciphertext = encrypted.sublist(0, encrypted.length - 16);

    final decoded = decryptAesGcmJson(
      key: key,
      ivBase64: base64Encode(iv),
      tagBase64: base64Encode(tag),
      ciphertextBase64: base64Encode(ciphertext),
    );

    expect(decoded['host'], '127.0.0.1');
    expect(decoded['port'], 22);
  });

  test('rejects keys that are not 32 bytes', () {
    expect(
      () => decryptAesGcmJson(
        key: Uint8List(16),
        ivBase64: base64Encode(Uint8List(12)),
        tagBase64: base64Encode(Uint8List(16)),
        ciphertextBase64: base64Encode(Uint8List(0)),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when auth tag has been tampered', () {
    final key = Uint8List.fromList(utf8.encode('0123456789abcdef0123456789abcdef'));
    final iv = Uint8List.fromList(List<int>.generate(12, (i) => i));
    final plaintext = Uint8List.fromList(utf8.encode('{"a":1}'));
    final encrypted = _encryptForTest(key, iv, plaintext);
    final tag = encrypted.sublist(encrypted.length - 16);
    final ciphertext = encrypted.sublist(0, encrypted.length - 16);

    final tampered = Uint8List.fromList(tag);
    tampered[0] ^= 0x01;

    expect(
      () => decryptAesGcmJson(
        key: key,
        ivBase64: base64Encode(iv),
        tagBase64: base64Encode(tampered),
        ciphertextBase64: base64Encode(ciphertext),
      ),
      throwsA(anything),
    );
  });
}
