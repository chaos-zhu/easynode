import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/auth/auth_session.dart';
import 'auth_state.dart';
import 'storage_providers.dart';
import 'terminal_providers.dart';

/// Single source of truth for "are we logged in?". Login flow calls
/// [signIn] after the controller succeeds; logout calls [signOut]. UI
/// observes this provider to swap between LoginPage and MainShellPage.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref, AuthState initial) : super(initial);

  final Ref _ref;

  Future<void> signIn({
    required AuthSession session,
    required ApiClient apiClient,
    required String publicKeyPem,
    String? passwordToSave,
  }) async {
    final appStorage = _ref.read(appStorageProvider);
    final secureStorage = _ref.read(secureStorageProvider);

    await appStorage.setServerAddress(session.serverAddress);
    await appStorage.setUsername(session.username);
    if (passwordToSave != null) {
      await appStorage.setSavePassword(true);
      await secureStorage.writePassword(
        session.serverAddress,
        session.username,
        passwordToSave,
      );
    } else {
      await appStorage.setSavePassword(false);
      await secureStorage.deletePassword(
        session.serverAddress,
        session.username,
      );
    }
    await secureStorage.writeToken(session.token);
    await secureStorage.writeDeviceId(session.deviceId);

    state = AuthState(
      session: session,
      apiClient: apiClient,
      publicKeyPem: publicKeyPem,
    );
  }

  Future<void> signOut() async {
    await _ref.read(terminalSessionManagerProvider).closeAll();
    final secureStorage = _ref.read(secureStorageProvider);
    final cookieStore = _ref.read(cookieStoreProvider);
    await secureStorage.deleteToken();
    await secureStorage.deleteDeviceId();
    await cookieStore.clear();
    state = AuthState.empty;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  throw UnimplementedError('authProvider must be overridden in bootstrap');
});
