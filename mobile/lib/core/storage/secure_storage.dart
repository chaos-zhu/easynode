import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hardware-backed secret store (Keystore on Android, Keychain on iOS).
/// Holds saved password (only when user opted in), login token, session
/// cookie, and any other high-sensitivity material.
class SecureAppStorage {
  SecureAppStorage(this._storage);
  final FlutterSecureStorage _storage;

  String _passwordKey(String serverAddress, String username) =>
      'password:$serverAddress:$username';

  Future<String?> readPassword(String serverAddress, String username) {
    return _storage.read(key: _passwordKey(serverAddress, username));
  }

  Future<void> writePassword(String serverAddress, String username, String password) {
    return _storage.write(key: _passwordKey(serverAddress, username), value: password);
  }

  Future<void> deletePassword(String serverAddress, String username) {
    return _storage.delete(key: _passwordKey(serverAddress, username));
  }

  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> writeToken(String token) => _storage.write(key: 'token', value: token);
  Future<void> deleteToken() => _storage.delete(key: 'token');

  Future<String?> readSessionCookie() => _storage.read(key: 'sessionCookie');
  Future<void> writeSessionCookie(String value) =>
      _storage.write(key: 'sessionCookie', value: value);
  Future<void> deleteSessionCookie() => _storage.delete(key: 'sessionCookie');
}
