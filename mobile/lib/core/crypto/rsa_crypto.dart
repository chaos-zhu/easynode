import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

/// Wraps RSA encryption against the EasyNode server public key fetched from
/// `/api/v1/get-pub-pem`. The server side uses node-rsa with PKCS1 padding
/// and decrypts to a utf8 string via `rsakey.decrypt(ct, 'utf8')`, so all
/// payloads here are passed through utf8 before encrypting.
class RsaCrypto {
  /// Encrypt the user login password. Matches the existing Web login flow.
  String encryptPassword(String publicKeyPem, String plaintext) {
    final engine = _engine(publicKeyPem);
    return base64Encode(engine.process(Uint8List.fromList(utf8.encode(plaintext))));
  }

  /// Encrypt a one-time AES key.
  ///
  /// The server-side handler does `Buffer.from(decryptedText, 'base64')` after
  /// RSA-decrypting to a utf8 string, so we base64-encode the raw key bytes
  /// before RSA-encrypting. This round-trip preserves the 32-byte binary key
  /// through the existing string-based RSA helper without changing the helper.
  String encryptTemporaryKey(String publicKeyPem, Uint8List keyBytes) {
    final engine = _engine(publicKeyPem);
    final base64Text = base64Encode(keyBytes);
    final encrypted = engine.process(Uint8List.fromList(utf8.encode(base64Text)));
    return base64Encode(encrypted);
  }

  AsymmetricBlockCipher _engine(String publicKeyPem) {
    final key = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
    return PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
  }
}
