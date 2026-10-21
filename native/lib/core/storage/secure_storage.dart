import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hardware-backed secret store (Keystore on Android, Keychain on iOS).
/// Holds saved password (only when user opted in), login token, session
/// cookie, and any other high-sensitivity material.
class SecureAppStorage {
  SecureAppStorage(this._storage);
  final FlutterSecureStorage _storage;
  String? _sessionCookie;
  bool _sessionCookieLoaded = false;

  String _passwordKey(String serverAddress, String username) =>
      'password:$serverAddress:$username';

  Future<String?> readPassword(String serverAddress, String username) {
    return _storage.read(key: _passwordKey(serverAddress, username));
  }

  Future<void> writePassword(
    String serverAddress,
    String username,
    String password,
  ) {
    return _storage.write(
      key: _passwordKey(serverAddress, username),
      value: password,
    );
  }

  Future<void> deletePassword(String serverAddress, String username) {
    return _storage.delete(key: _passwordKey(serverAddress, username));
  }

  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> writeToken(String token) =>
      _storage.write(key: 'token', value: token);
  Future<void> deleteToken() => _storage.delete(key: 'token');

  /// Load once for this app session. REST and socket clients share this
  /// wrapper, including writes made directly by the login coordinator.
  Future<String?> readSessionCookie() async {
    if (!_sessionCookieLoaded) {
      _sessionCookie = await _storage.read(key: 'sessionCookie');
      _sessionCookieLoaded = true;
    }
    return _sessionCookie;
  }

  Future<void> writeSessionCookie(String value) async {
    if (_sessionCookieLoaded && _sessionCookie == value) return;
    await _storage.write(key: 'sessionCookie', value: value);
    _sessionCookie = value;
    _sessionCookieLoaded = true;
  }

  Future<void> deleteSessionCookie() async {
    // Stop sending the cookie immediately, even if persistence cleanup fails.
    _sessionCookie = null;
    _sessionCookieLoaded = true;
    await _storage.delete(key: 'sessionCookie');
  }

  /// Server-issued login deviceId for the active session. Kept around for the
  /// future `DELETE /api/v1/revoke-login/:deviceId` flow.
  Future<String?> readDeviceId() => _storage.read(key: 'loginDeviceId');
  Future<void> writeDeviceId(String value) =>
      _storage.write(key: 'loginDeviceId', value: value);
  Future<void> deleteDeviceId() => _storage.delete(key: 'loginDeviceId');

  String _certificateFingerprintKey(String serverOrigin) =>
      'serverCertificateFingerprint:$serverOrigin';

  Future<String?> readServerCertificateFingerprint(String serverOrigin) {
    return _storage.read(key: _certificateFingerprintKey(serverOrigin));
  }

  Future<void> writeServerCertificateFingerprint(
    String serverOrigin,
    String fingerprint,
  ) {
    return _storage.write(
      key: _certificateFingerprintKey(serverOrigin),
      value: fingerprint,
    );
  }
}
