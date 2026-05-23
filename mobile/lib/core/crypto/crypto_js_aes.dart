import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encrypts like `CryptoJS.AES.encrypt(text, passphrase).toString()`.
///
/// EasyNode's web form submits secrets in CryptoJS' OpenSSL-compatible
/// passphrase format: base64("Salted__" + 8-byte salt + AES-CBC ciphertext).
String encryptCryptoJsAes(String plaintext, String passphrase, {Random? random}) {
  final rng = random ?? Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(8, (_) => rng.nextInt(256)));
  final keyIv = _evpBytesToKey(
    utf8.encode(passphrase),
    salt,
    keyLength: 32,
    ivLength: 16,
  );
  final padded = _pkcs7Pad(Uint8List.fromList(utf8.encode(plaintext)), 16);
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      true,
      ParametersWithIV<KeyParameter>(
        KeyParameter(keyIv.key),
        keyIv.iv,
      ),
    );
  final encrypted = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += cipher.blockSize) {
    cipher.processBlock(padded, offset, encrypted, offset);
  }
  final envelope = Uint8List(16 + encrypted.length)
    ..setRange(0, 8, utf8.encode('Salted__'))
    ..setRange(8, 16, salt)
    ..setRange(16, 16 + encrypted.length, encrypted);
  return base64Encode(envelope);
}

({Uint8List key, Uint8List iv}) _evpBytesToKey(
  List<int> passphrase,
  Uint8List salt, {
  required int keyLength,
  required int ivLength,
}) {
  final targetLength = keyLength + ivLength;
  final bytes = BytesBuilder(copy: false);
  var previous = Uint8List(0);
  while (bytes.length < targetLength) {
    final digest = Digest('MD5');
    digest.update(previous, 0, previous.length);
    digest.update(Uint8List.fromList(passphrase), 0, passphrase.length);
    digest.update(salt, 0, salt.length);
    previous = digest.process(Uint8List(0));
    bytes.add(previous);
  }
  final material = bytes.toBytes();
  return (
    key: Uint8List.fromList(material.sublist(0, keyLength)),
    iv: Uint8List.fromList(material.sublist(keyLength, targetLength)),
  );
}

Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
  final padLength = blockSize - (data.length % blockSize);
  return Uint8List(data.length + padLength)
    ..setRange(0, data.length, data)
    ..fillRange(data.length, data.length + padLength, padLength);
}
