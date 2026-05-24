import 'dart:convert';
import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/crypto/cryptojs_aes.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../servers/server_proxy_model.dart';
import 'models/login_session.dart';
import 'models/plus_info.dart';

/// Repository for the Account / Plus / Sessions / Proxy CRUD / Credential
/// CRUD endpoints. Plus / Sessions / Proxy / Credentials list reads still
/// live in their existing dedicated notifiers; this class only adds the
/// write paths + extras the notifiers don't cover.
class SettingsRepository {
  SettingsRepository({
    required this.apiClient,
    required this.publicKeyPem,
    CryptoJsAes? aes,
    RsaCrypto? rsa,
  })  : _aes = aes ?? CryptoJsAes(),
        _rsa = rsa ?? RsaCrypto();

  final ApiClient apiClient;
  final String publicKeyPem;
  final CryptoJsAes _aes;
  final RsaCrypto _rsa;

  // ---- Account / password ----

  /// `PUT /pwd` with RSA-encrypted old + new password.
  Future<void> updateAccount({
    required String oldLoginName,
    required String oldPwd,
    required String newLoginName,
    required String newPwd,
  }) async {
    final body = <String, dynamic>{
      'oldLoginName': oldLoginName,
      'newLoginName': newLoginName,
      'oldPwd': _rsa.encryptPassword(publicKeyPem, oldPwd),
      'newPwd': _rsa.encryptPassword(publicKeyPem, newPwd),
    };
    await apiClient.putJson('/pwd', body);
  }

  // ---- MFA2 ----

  Future<bool> getMfa2Status() async {
    final res = await apiClient.getJson('/mfa2-status');
    final raw = res['data'];
    return raw == true || raw == 1 || raw == '1';
  }

  /// `POST /mfa2-code` -> `{ data: { qrImage, secret } }`.
  Future<Mfa2Setup> getMfa2QrInfo() async {
    final res = await apiClient.postJson('/mfa2-code', const {});
    final raw = res['data'];
    if (raw is! Map) {
      throw StateError('mfa2-code returned unexpected payload');
    }
    return Mfa2Setup(
      qrImage: (raw['qrImage'] ?? '').toString(),
      secret: (raw['secret'] ?? '').toString(),
    );
  }

  Future<void> enableMfa2(String token) async {
    await apiClient.postJson('/mfa2-enable', {'token': token});
  }

  Future<void> disableMfa2(String token) async {
    await apiClient.postJson('/mfa2-disable', {'token': token});
  }

  // ---- Plus ----

  Future<PlusInfo> getPlusInfo() async {
    final res = await apiClient.getJson('/plus-info');
    final raw = res['data'];
    if (raw is! Map || raw.isEmpty) return PlusInfo.empty();
    return PlusInfo.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<String> getPlusKey() async {
    final res = await apiClient.getJson('/plus-conf');
    final raw = res['data'];
    return raw == null ? '' : raw.toString();
  }

  Future<void> updatePlusKey(String key) async {
    await apiClient.postJson('/plus-conf', {'key': key});
  }

  Future<PlusDiscount> getPlusDiscount() async {
    try {
      final res = await apiClient.getJson('/plus-discount');
      final raw = res['data'];
      if (raw is Map) {
        return PlusDiscount.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // /plus-discount is optional; treat any error as "no discount".
    }
    return const PlusDiscount(discount: false, content: '');
  }

  // ---- Sessions ----

  Future<LoginLogData> getLoginLog() async {
    final res = await apiClient.getJson('/log');
    final raw = res['data'];
    if (raw is! Map) return const LoginLogData(sessions: [], ipWhiteList: []);
    return LoginLogData.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> saveIpWhiteList(List<String> whitelist) async {
    await apiClient.postJson('/ip-white-list', {'ipWhiteList': whitelist});
  }

  Future<void> revokeSession(String idOrDeviceId) async {
    await apiClient.deleteJson('/revoke-login/$idOrDeviceId');
  }

  Future<void> purgeOldSessions() async {
    await apiClient.deleteJson('/remove-some-login-records');
  }

  // ---- Proxies CRUD ----

  Future<void> createProxy(ServerProxyModel proxy) async {
    await apiClient.postJson('/proxy', _proxyBody(proxy));
  }

  Future<void> updateProxy(ServerProxyModel proxy) async {
    await apiClient.putJson('/proxy/${proxy.id}', _proxyBody(proxy));
  }

  Future<void> deleteProxy(String id) async {
    await apiClient.deleteJson('/proxy/$id');
  }

  Map<String, dynamic> _proxyBody(ServerProxyModel proxy) => {
        'type': proxy.type,
        'name': proxy.name,
        'host': proxy.host,
        'port': proxy.port,
        'username': proxy.username,
        'password': proxy.password,
      };

  // ---- Credentials CRUD ----

  /// `POST /add-ssh`. Secrets are AES-encrypted with a one-time tempKey,
  /// tempKey itself is RSA-encrypted with the server public key.
  Future<void> createCredential({
    required String name,
    required String authType,
    String password = '',
    String privateKey = '',
    String openSSHKeyPassword = '',
  }) async {
    final body = _credentialBody(
      name: name,
      authType: authType,
      password: password,
      privateKey: privateKey,
      openSSHKeyPassword: openSSHKeyPassword,
    );
    await apiClient.postJson('/add-ssh', body);
  }

  /// `POST /update-ssh`.
  Future<void> updateCredential({
    required String id,
    required String name,
    required String authType,
    String password = '',
    String privateKey = '',
    String openSSHKeyPassword = '',
  }) async {
    final body = _credentialBody(
      name: name,
      authType: authType,
      password: password,
      privateKey: privateKey,
      openSSHKeyPassword: openSSHKeyPassword,
    )..['id'] = id;
    await apiClient.postJson('/update-ssh', body);
  }

  Future<void> deleteCredential(String id) async {
    await apiClient.deleteJson('/remove-ssh/$id');
  }

  Map<String, dynamic> _credentialBody({
    required String name,
    required String authType,
    required String password,
    required String privateKey,
    required String openSSHKeyPassword,
  }) {
    final tempKey = _aes.generateTempKey();
    String encPassword = '';
    String encPrivateKey = '';
    String encOpenSSHKeyPassword = '';
    if (authType == 'password' && password.isNotEmpty) {
      encPassword = _aes.encrypt(password, tempKey);
    }
    if (authType == 'privateKey' && privateKey.isNotEmpty) {
      encPrivateKey = _aes.encrypt(privateKey, tempKey);
    }
    if (openSSHKeyPassword.isNotEmpty) {
      encOpenSSHKeyPassword = _aes.encrypt(openSSHKeyPassword, tempKey);
    }
    final rsaTempKey = _rsa.encryptPassword(publicKeyPem, tempKey);
    return <String, dynamic>{
      'name': name,
      'authType': authType,
      'password': encPassword,
      'privateKey': encPrivateKey,
      'openSSHKeyPassword': encOpenSSHKeyPassword,
      'tempKey': rsaTempKey,
    };
  }
}

class Mfa2Setup {
  const Mfa2Setup({required this.qrImage, required this.secret});

  final String qrImage; // data:image/png;base64,...
  final String secret;

  /// Decode the data-URL payload to raw PNG bytes for Image.memory.
  Uint8List? get qrImageBytes {
    final marker = 'base64,';
    final idx = qrImage.indexOf(marker);
    if (idx < 0) return null;
    return base64Decode(qrImage.substring(idx + marker.length));
  }
}
