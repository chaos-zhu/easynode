import '../core/api/api_client.dart';
import '../features/auth/auth_session.dart';

/// Snapshot of authenticated-app state. A saved session and API client allow
/// offline restoration; the public key is loaded when encryption is needed.
/// Protected requests validate the session once the server is reachable.
class AuthState {
  const AuthState({this.session, this.apiClient, this.publicKeyPem});

  final AuthSession? session;
  final ApiClient? apiClient;
  final String? publicKeyPem;

  bool get signedIn => session != null && apiClient != null;

  static const empty = AuthState();

  AuthState copyWith({
    AuthSession? session,
    ApiClient? apiClient,
    String? publicKeyPem,
  }) {
    return AuthState(
      session: session ?? this.session,
      apiClient: apiClient ?? this.apiClient,
      publicKeyPem: publicKeyPem ?? this.publicKeyPem,
    );
  }
}
