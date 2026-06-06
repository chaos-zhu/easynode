/// Active authentication state for the running app.
class AuthSession {
  const AuthSession({
    required this.serverAddress,
    required this.username,
    required this.token,
    required this.deviceId,
  });

  /// Normalized server address (no trailing slash).
  final String serverAddress;
  final String username;

  /// The server-issued login token (already AES-encrypted by the server,
  /// passed back as-is in the `token` header).
  final String token;

  /// The server-issued login `deviceId`. Used by the existing
  /// `/api/v1/revoke-login/:deviceId` endpoint to invalidate this session.
  final String deviceId;
}
