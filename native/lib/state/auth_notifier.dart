import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/storage/app_storage.dart';
import '../features/auth/auth_session.dart';
import 'docker_providers.dart';
import 'auth_state.dart';
import 'plus_info_notifier.dart';
import 'storage_providers.dart';
import 'terminal_providers.dart';

/// Single source of truth for "are we logged in?". Login flow calls
/// [signIn] after the controller succeeds; logout calls [signOut]. UI
/// observes this provider to swap between LoginPage and MainShellPage.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref, AuthState initial) : super(initial);

  final Ref _ref;
  Future<void>? _pendingCleanup;

  Future<void> signIn({
    required AuthSession session,
    required ApiClient apiClient,
    required String publicKeyPem,
    String? passwordToSave,
    String? sessionCookie,
  }) async {
    await _pendingCleanup;
    final appStorage = _ref.read(appStorageProvider);
    final secureStorage = _ref.read(secureStorageProvider);

    try {
      // Token is the commit marker. A crash or storage failure during the
      // remaining writes must not restore a partially committed session.
      await secureStorage.deleteToken();
      if (passwordToSave != null) {
        await secureStorage.writePassword(
          session.serverAddress,
          session.username,
          passwordToSave,
        );
      } else {
        await secureStorage.deletePassword(
          session.serverAddress,
          session.username,
        );
      }
      await appStorage.upsertSavedLoginAccount(
        SavedLoginAccount(
          serverAddress: session.serverAddress,
          username: session.username,
          savePassword: passwordToSave != null,
        ),
      );
      await secureStorage.writeDeviceId(session.deviceId);
      if (sessionCookie != null) {
        await secureStorage.writeSessionCookie(sessionCookie);
      }
      await secureStorage.writeToken(session.token);
    } catch (_) {
      // Attempt every cleanup independently; one failed deletion must not
      // prevent the other secrets from being removed.
      for (final cleanup in <Future<void> Function()>[
        secureStorage.deleteToken,
        secureStorage.deleteDeviceId,
        secureStorage.deleteSessionCookie,
      ]) {
        try {
          await cleanup();
        } catch (_) {}
      }
      rethrow;
    }

    state = AuthState(
      session: session,
      apiClient: apiClient,
      publicKeyPem: publicKeyPem,
    );
    // Repositories and Plus info watch auth and rebuild for the new session.
  }

  Future<void> signOut() => _signOut();

  /// During startup there are no usable feature pages to unblock. Keep the
  /// connection page mounted until old credentials are deleted, so a new
  /// login cannot race with that deletion.
  Future<void> signOutAfterCleanup() => _signOut(clearAuthFirst: false);

  /// Interactive desktop sign-out keeps the retry action available if the
  /// system secret store refuses a deletion.
  Future<void> signOutSafely() =>
      _signOut(clearAuthFirst: false, reportCleanupFailure: true);

  Future<void> _signOut({
    bool clearAuthFirst = true,
    bool reportCleanupFailure = false,
  }) async {
    final pending = _pendingCleanup;
    if (pending != null) return pending;
    final cleanup = _performSignOut(
      clearAuthFirst: clearAuthFirst,
      reportCleanupFailure: reportCleanupFailure,
    );
    _pendingCleanup = cleanup;
    try {
      await cleanup;
    } finally {
      _pendingCleanup = null;
    }
  }

  Future<void> _performSignOut({
    required bool clearAuthFirst,
    required bool reportCleanupFailure,
  }) async {
    // Active feature pages must leave immediately even if cleanup fails.
    // Startup can wait on its connection page to avoid exposing a new login
    // while the old credentials are still being deleted.
    final previousApi = state.apiClient;
    if (clearAuthFirst) state = AuthState.empty;
    try {
      await _ref.read(terminalSessionManagerProvider).closeAll();
    } catch (_) {}
    try {
      await _ref.read(sftpSessionManagerProvider).disconnectAll();
    } catch (_) {}
    try {
      _ref.read(dockerSessionManagerProvider).disconnectAll();
    } catch (_) {}
    // Stop late responses from restoring cookies after cleanup.
    await previousApi?.close();
    Object? cleanupFailure;
    final secureStorage = _ref.read(secureStorageProvider);
    for (final cleanup in <Future<void> Function()>[
      secureStorage.deleteToken,
      secureStorage.deleteDeviceId,
      _ref.read(cookieStoreProvider).clear,
    ]) {
      try {
        await cleanup();
      } catch (error) {
        cleanupFailure ??= error;
      }
    }
    if (reportCleanupFailure && cleanupFailure != null) throw cleanupFailure;
    if (!clearAuthFirst && mounted) state = AuthState.empty;
    try {
      _ref.invalidate(plusInfoProvider);
    } catch (_) {}
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  throw UnimplementedError('authProvider must be overridden in bootstrap');
});
