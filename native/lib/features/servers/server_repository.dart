import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/crypto/aes_gcm_crypto.dart';
import '../../core/crypto/crypto_js_aes.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../terminal/ssh_connection_config.dart';
import '../shell/sftp_session_manager.dart';
import 'server_form_data.dart';
import 'server_group_model.dart';
import 'server_model.dart';

/// Backs the server list page and the connect action. The interface lets
/// widget tests inject a fake without touching real HTTP / RSA code.
abstract class ServerRepository {
  Future<List<ServerModel>> fetchHosts();
  Future<List<ServerGroupModel>> fetchGroups();
  Future<String> createHost(ServerFormData form);
  Future<String> updateHost(ServerFormData form);
  Future<String> deleteHost(String hostId);
  Future<SshConnectionConfig> fetchSshConfig(String hostId);
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId);
}

/// Default [ServerRepository] backed by [ApiClient] and the RSA public key
/// fetched at login time.
class ApiServerRepository implements ServerRepository {
  ApiServerRepository({
    required ApiClient apiClient,
    required String publicKeyPem,
    RsaCrypto? rsa,
    Random? random,
  }) : _api = apiClient,
       _publicKeyPem = publicKeyPem,
       _rsa = rsa ?? RsaCrypto(),
       _random = random ?? Random.secure();

  final ApiClient _api;
  final String _publicKeyPem;
  final RsaCrypto _rsa;
  final Random _random;

  /// Fetch the host list. Server returns `{ data: [host...] }`.
  @override
  Future<List<ServerModel>> fetchHosts() async {
    final response = await _api.getJson('/host-list');
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ServerModel.fromJson)
        .toList(growable: false);
  }

  /// Fetch the server group list. Server returns `{ data: [group...] }`.
  @override
  Future<List<ServerGroupModel>> fetchGroups() async {
    final response = await _api.getJson('/group');
    final raw = response['data'];
    if (raw is! List) return const [];
    final groups = raw
        .whereType<Map<String, dynamic>>()
        .map(ServerGroupModel.fromJson)
        .toList(growable: false);
    groups.sort((a, b) => b.index.compareTo(a.index));
    return groups;
  }

  @override
  Future<String> createHost(ServerFormData form) async {
    final response = await _api.postJson(
      '/host-save',
      _prepareHostPayload(form),
    );
    return response['msg']?.toString() ?? 'success';
  }

  @override
  Future<String> updateHost(ServerFormData form) async {
    final response = await _api.putJson(
      '/host-save',
      _prepareHostPayload(form),
    );
    return response['msg']?.toString() ?? 'success';
  }

  @override
  Future<String> deleteHost(String hostId) async {
    final response = await _api.postJson('/host-remove', {
      'ids': [hostId],
    });
    return response['data']?.toString() ??
        response['msg']?.toString() ??
        'success';
  }

  Map<String, dynamic> _prepareHostPayload(ServerFormData form) {
    final payload = form.toJson();
    final authType = payload['authType']?.toString() ?? '';
    final secret = payload[authType]?.toString() ?? '';
    if (authType.isNotEmpty && secret.isNotEmpty) {
      final tempKey = _randomText(16);
      payload[authType] = encryptCryptoJsAes(secret, tempKey, random: _random);
      payload['tempKey'] = _rsa.encryptPassword(_publicKeyPem, tempKey);
    }
    return payload;
  }

  /// Request decrypted SSH connection parameters for [hostId].
  ///
  /// 1. Generate a fresh 32-byte AES key.
  /// 2. RSA-encrypt it with the public key fetched at login time.
  /// 3. POST to `/native/ssh-connection`.
  /// 4. AES-GCM-decrypt the response envelope.
  /// 5. Return a strongly typed [SshConnectionConfig].
  ///
  /// The temporary key and decrypted payload live only inside this method.
  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    final keyBytes = _randomBytes(32);
    final encryptedKey = _rsa.encryptTemporaryKey(_publicKeyPem, keyBytes);
    final response = await _api.postJson('/native/ssh-connection', {
      'hostId': hostId,
      'encryptedKey': encryptedKey,
    });
    if (response['status'] != 200) {
      throw ApiFailure(response['msg']?.toString() ?? '获取 SSH 连接参数失败');
    }
    final data = response['data'];
    if (data is! Map) {
      throw ApiFailure('SSH 连接响应格式异常');
    }
    final iv = data['iv'];
    final tag = data['tag'];
    final ciphertext = data['ciphertext'];
    if (iv is! String || tag is! String || ciphertext is! String) {
      throw ApiFailure('SSH 连接响应缺少字段');
    }

    final Map<String, dynamic> plaintext;
    try {
      plaintext = decryptAesGcmJson(
        key: keyBytes,
        ivBase64: iv,
        tagBase64: tag,
        ciphertextBase64: ciphertext,
      );
    } catch (_) {
      throw ApiFailure('SSH 连接参数解密失败');
    }

    return SshConnectionConfig.fromJson(plaintext);
  }

  @override
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId) async {
    final response = await _api.getJson('/sftp/favorites/$hostId');
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SftpFavorite.fromJson)
        .toList(growable: false);
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  String _randomText(int length) {
    const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
    return String.fromCharCodes(
      List<int>.generate(
        length,
        (_) => chars.codeUnitAt(_random.nextInt(chars.length)),
      ),
    );
  }

  /// Expose so [ApiServerRepository] can be JSON-serialized in widget tests.
  // ignore: unused_element
  String _debugBase64Bytes(Uint8List bytes) => base64Encode(bytes);
}
