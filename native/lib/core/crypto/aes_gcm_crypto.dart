import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Decrypts an AES-256-GCM envelope produced by `server/app/utils/mobile-crypto.js`.
///
/// The Node side returns three base64 strings — `iv`, `tag`, and `ciphertext` —
/// that come out of `crypto.createCipheriv('aes-256-gcm', key, iv)`. PointyCastle's
/// `GCMBlockCipher` expects ciphertext concatenated with the auth tag, so we
/// decode each component and rebuild the combined buffer before processing.
Map<String, dynamic> decryptAesGcmJson({
  required Uint8List key,
  required String ivBase64,
  required String tagBase64,
  required String ciphertextBase64,
}) {
  if (key.length != 32) {
    throw ArgumentError('temporary key must be 32 bytes');
  }
  final iv = base64Decode(ivBase64);
  final tag = base64Decode(tagBase64);
  final ciphertext = base64Decode(ciphertextBase64);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, Uint8List.fromList(iv), Uint8List(0)),
    );

  final combined = Uint8List(ciphertext.length + tag.length)
    ..setRange(0, ciphertext.length, ciphertext)
    ..setRange(ciphertext.length, ciphertext.length + tag.length, tag);

  final plaintext = cipher.process(combined);
  return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
}
