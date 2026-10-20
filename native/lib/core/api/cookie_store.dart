import '../storage/secure_storage.dart';

/// Persists the EasyNode `session` cookie in secure storage and rehydrates
/// it on every request. The cookie is the second half of EasyNode's auth
/// pair (token header + session cookie), so it must survive process restarts.
class SessionCookieStore {
  SessionCookieStore(this._storage);

  /// A login attempt must never read or overwrite the active account's cookie.
  SessionCookieStore.memory() : _storage = null;

  final SecureAppStorage? _storage;
  String? _cookie;

  bool get isTransient => _storage == null;

  /// Look for `session=...` inside a `Set-Cookie` header list and persist it.
  /// Other cookies are ignored; EasyNode does not use them.
  Future<void> saveFromSetCookieHeaders(List<String> headers) async {
    for (final header in headers) {
      final firstPart = header.split(';').first.trim();
      if (firstPart.startsWith('session=')) {
        final storage = _storage;
        if (storage == null) {
          _cookie = firstPart;
        } else {
          await storage.writeSessionCookie(firstPart);
        }
        return;
      }
    }
  }

  Future<String?> readCookieHeader() async =>
      _storage == null ? _cookie : await _storage.readSessionCookie();

  Future<void> clear() async {
    _cookie = null;
    await _storage?.deleteSessionCookie();
  }
}
