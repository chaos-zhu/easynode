import '../storage/secure_storage.dart';

/// Persists the EasyNode `session` cookie in secure storage and rehydrates
/// it on every request. The cookie is the second half of EasyNode's auth
/// pair (token header + session cookie), so it must survive process restarts.
class SessionCookieStore {
  SessionCookieStore(this._storage);
  final SecureAppStorage _storage;

  /// Look for `session=...` inside a `Set-Cookie` header list and persist it.
  /// Other cookies are ignored; EasyNode does not use them.
  Future<void> saveFromSetCookieHeaders(List<String> headers) async {
    for (final header in headers) {
      final firstPart = header.split(';').first.trim();
      if (firstPart.startsWith('session=')) {
        await _storage.writeSessionCookie(firstPart);
        return;
      }
    }
  }

  Future<String?> readCookieHeader() => _storage.readSessionCookie();
  Future<void> clear() => _storage.deleteSessionCookie();
}
