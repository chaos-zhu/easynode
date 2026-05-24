import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/scripts/script_repository.dart';
import '../features/servers/server_repository.dart';
import 'auth_notifier.dart';

/// Resolves the active [ApiClient] from the auth state. Pages should not
/// build their own ApiClient; they ask this provider so a re-login swap is
/// observed automatically.
final apiClientProvider = Provider<ApiClient>((ref) {
  final api = ref.watch(authProvider).apiClient;
  if (api == null) {
    throw StateError('apiClientProvider read while signed out');
  }
  return api;
});

/// Repository for `/host-list` and `/mobile/ssh-connection`. Depends on the
/// active ApiClient and the public key fetched at login time, both of
/// which are derived from [authProvider].
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final auth = ref.watch(authProvider);
  final api = auth.apiClient;
  final pubKey = auth.publicKeyPem;
  if (api == null || pubKey == null) {
    throw StateError('serverRepositoryProvider read while signed out');
  }
  return ApiServerRepository(apiClient: api, publicKeyPem: pubKey);
});

/// Repository for `/script` and `/script-group`. Only needs the ApiClient
/// — scripts don't go through the RSA/AES envelope SSH connections use.
final scriptRepositoryProvider = Provider<ScriptRepository>((ref) {
  final api = ref.watch(authProvider).apiClient;
  if (api == null) {
    throw StateError('scriptRepositoryProvider read while signed out');
  }
  return ApiScriptRepository(apiClient: api);
});
