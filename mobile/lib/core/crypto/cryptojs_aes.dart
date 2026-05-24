import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// CryptoJS-compatible AES-CBC encryption.
///
/// When CryptoJS.AES.encrypt is called with a string passphrase (not a
/// WordArray), it derives a 32-byte key + 16-byte IV from `passphrase` and an
/// 8-byte random salt using OpenSSL's EVP_BytesToKey with MD5 (1 iteration).
/// The output format is base64 of:
///
///     "Salted__" (8 bytes ASCII) | salt (8 bytes) | ciphertext (AES-256-CBC, PKCS#7)
///
/// The EasyNode server side uses `crypto-js` to decrypt — matching this exact
/// format is required for `/add-ssh` / `/update-ssh` / `/pwd` / `/proxy` POSTs
/// that carry secrets encrypted with a one-time tempKey.
class CryptoJsAes {
  CryptoJsAes({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// Encrypts [plaintext] with the given UTF-8 passphrase and returns the
  /// base64 envelope CryptoJS produces.
  String encrypt(String plaintext, String passphrase) {
    final salt = Uint8List.fromList(
      List<int>.generate(8, (_) => _random.nextInt(256)),
    );
    final passphraseBytes = Uint8List.fromList(utf8.encode(passphrase));
    final (key, iv) = _evpKdf(passphraseBytes, salt, keyLen: 32, ivLen: 16);

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    final ciphertext = cipher.process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

    final out = BytesBuilder()
      ..add(utf8.encode('Salted__'))
      ..add(salt)
      ..add(ciphertext);
    return base64Encode(out.toBytes());
  }

  /// OpenSSL EVP_BytesToKey with MD5, 1 iteration.
  (Uint8List key, Uint8List iv) _evpKdf(
    Uint8List password,
    Uint8List salt, {
    required int keyLen,
    required int ivLen,
  }) {
    final total = keyLen + ivLen;
    final out = BytesBuilder();
    Uint8List prev = Uint8List(0);
    while (out.length < total) {
      final md5 = MD5Digest();
      md5.update(prev, 0, prev.length);
      md5.update(password, 0, password.length);
      md5.update(salt, 0, salt.length);
      prev = Uint8List(md5.digestSize);
      md5.doFinal(prev, 0);
      out.add(prev);
    }
    final keyAndIv = out.toBytes();
    return (
      Uint8List.sublistView(keyAndIv, 0, keyLen),
      Uint8List.sublistView(keyAndIv, keyLen, keyLen + ivLen),
    );
  }

  /// Random alphanumeric string suitable as the one-time tempKey passphrase
  /// (matches `Math.random().toString(36)` style keys used in the web).
  String generateTempKey({int length = 16}) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }
}
