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
import '../order/order_layout.dart';

class HostCatalog {
  const HostCatalog({
    required this.hosts,
    required this.groups,
    required this.order,
  });

  final List<ServerModel> hosts;
  final List<ServerGroupModel> groups;
  final OrderLayout order;

  factory HostCatalog.fromJson(Map<String, dynamic> json) => HostCatalog(
    hosts: (json['hosts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ServerModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false),
    groups: (json['groups'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ServerGroupModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false),
    order: OrderLayout.fromJson(
      (json['order'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    ),
  );
}

/// Backs the server list page and the connect action. The interface lets
/// widget tests inject a fake without touching real HTTP / RSA code.
abstract class ServerRepository {
  Future<List<ServerModel>> fetchHosts();
  Future<List<ServerGroupModel>> fetchGroups();
  Future<HostCatalog> fetchCatalog() async => HostCatalog(
    hosts: await fetchHosts(),
    groups: await fetchGroups(),
    order: const OrderLayout(schemaVersion: 1, revision: 0, sections: []),
  );

  /// Waits for reads started before a mutation notice without reusing their data.
  Future<void> settlePendingCatalog() async {}
  Future<OrderLayout> updateOrder(int revision, List<OrderChange> changes) =>
      throw UnsupportedError('Host ordering is not supported');
  Future<String> createHost(ServerFormData form);
  Future<String> updateHost(ServerFormData form);
  Future<String> deleteHost(String hostId);
  Future<SshConnectionConfig> fetchSshConfig(String hostId);
  Future<List<SftpFavorite>> fetchSftpFavorites(String hostId);
}

/// Default [ServerRepository] backed by [ApiClient] and the RSA public key
/// fetched on demand after session restore.
class ApiServerRepository implements ServerRepository {
  ApiServerRepository({
    required ApiClient apiClient,
    String? publicKeyPem,
    RsaCrypto? rsa,
    Random? random,
  }) : _api = apiClient,
       _publicKeyPem = publicKeyPem,
       _rsa = rsa ?? RsaCrypto(),
       _random = random ?? Random.secure();

  final ApiClient _api;
  final String? _publicKeyPem;
  final RsaCrypto _rsa;
  final Random _random;
  Future<HostCatalog>? _catalogRequest;

  Future<HostCatalog> _loadCatalog() {
    final pending = _catalogRequest;
    if (pending != null) return pending;
    final request = _fetchCatalog();
    _catalogRequest = request;
    request.then<void>(
      (_) {
        if (identical(_catalogRequest, request)) _catalogRequest = null;
      },
      onError: (_) {
        if (identical(_catalogRequest, request)) _catalogRequest = null;
      },
    );
    return request;
  }

  Future<HostCatalog> _fetchCatalog() async {
    final response = await _api.getJson('/host-catalog');
    final data = response['data'];
    if (data is! Map) {
      return const HostCatalog(
        hosts: [],
        groups: [],
        order: OrderLayout(schemaVersion: 1, revision: 0, sections: []),
      );
    }
    return HostCatalog.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<List<ServerModel>> fetchHosts() async {
    return (await _loadCatalog()).hosts;
  }

  /// Fetch the server group list. Server returns `{ data: [group...] }`.
  @override
  Future<List<ServerGroupModel>> fetchGroups() async {
    return (await _loadCatalog()).groups;
  }

  @override
  Future<HostCatalog> fetchCatalog() => _loadCatalog();

  @override
  Future<void> settlePendingCatalog() async {
    try {
      await _catalogRequest;
    } catch (_) {
      // The next refresh retries; an earlier read failure is not its result.
    }
  }

  @override
  Future<OrderLayout> updateOrder(
    int revision,
    List<OrderChange> changes,
  ) async {
    final response = await _api.putJson('/host-order', {
      'revision': revision,
      'changes': changes.map((change) => change.toJson()).toList(),
    });
    final data = response['data'];
    if (data is! Map) throw ApiFailure('排序响应格式异常');
    return OrderLayout.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<String> createHost(ServerFormData form) async {
    final response = await _api.postJson(
      '/host-save',
      await _prepareHostPayload(form),
    );
    return response['msg']?.toString() ?? 'success';
  }

  @override
  Future<String> updateHost(ServerFormData form) async {
    final response = await _api.putJson(
      '/host-save',
      await _prepareHostPayload(form),
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

  Future<Map<String, dynamic>> _prepareHostPayload(ServerFormData form) async {
    final payload = form.toJson();
    final authType = payload['authType']?.toString() ?? '';
    final secret = payload[authType]?.toString() ?? '';
    if (authType.isNotEmpty && secret.isNotEmpty) {
      final tempKey = _randomText(16);
      payload[authType] = encryptCryptoJsAes(secret, tempKey, random: _random);
      payload['tempKey'] = _rsa.encryptPassword(
        _publicKeyPem ?? await _api.getPublicKey(),
        tempKey,
      );
    }
    return payload;
  }

  /// Request decrypted SSH connection parameters for [hostId].
  ///
  /// 1. Generate a fresh 32-byte AES key.
  /// 2. RSA-encrypt it with the server public key (loaded on demand).
  /// 3. POST to `/native/ssh-connection`.
  /// 4. AES-GCM-decrypt the response envelope.
  /// 5. Return a strongly typed [SshConnectionConfig].
  ///
  /// The temporary key and decrypted payload live only inside this method.
  @override
  Future<SshConnectionConfig> fetchSshConfig(String hostId) async {
    final keyBytes = _randomBytes(32);
    final encryptedKey = _rsa.encryptTemporaryKey(
      _publicKeyPem ?? await _api.getPublicKey(),
      keyBytes,
    );
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
