import '../core/api/api_client.dart';
import '../features/auth/auth_session.dart';

/// Snapshot of authenticated-app state. `signedIn` requires all three fields
/// to be present; the UI uses that flag to decide between login and main
/// shell without re-checking the underlying nullables in every consumer.
class AuthState {
  const AuthState({this.session, this.apiClient, this.publicKeyPem});

  final AuthSession? session;
  final ApiClient? apiClient;
  final String? publicKeyPem;

  bool get signedIn =>
      session != null && apiClient != null && publicKeyPem != null;

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
