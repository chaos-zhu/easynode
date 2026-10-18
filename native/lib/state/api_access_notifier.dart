import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import 'auth_notifier.dart';

class ApiAccessState {
  const ApiAccessState({this.signOutReason, this.ipAccessDenied = false});

  final String? signOutReason;
  final bool ipAccessDenied;

  static const empty = ApiAccessState();
}

/// Owns all application-wide side effects caused by REST session failures.
/// Feature pages and data notifiers only handle their local business errors.
class ApiAccessNotifier extends StateNotifier<ApiAccessState> {
  ApiAccessNotifier(this._ref, [ApiAccessState initial = ApiAccessState.empty])
    : super(initial);

  final Ref _ref;
  Future<void>? _forcedSignOutFuture;

  Future<void> handleSessionFailure(
    ApiSessionFailure failure, {
    bool waitForCleanup = false,
  }) async {
    if (failure is IpAccessDeniedFailure) {
      markIpAccessDenied();
      return;
    }

    final pending = _forcedSignOutFuture;
    if (pending != null) {
      await pending;
      return;
    }
    state = ApiAccessState(signOutReason: failure.message);
    final auth = _ref.read(authProvider.notifier);
    final signOut = waitForCleanup
        ? auth.signOutAfterCleanup()
        : auth.signOut();
    _forcedSignOutFuture = signOut;
    await signOut;
  }

  void markIpAccessDenied() {
    if (state.ipAccessDenied) return;
    state = ApiAccessState(
      signOutReason: state.signOutReason,
      ipAccessDenied: true,
    );
  }

  void consumeSignOutReason() {
    if (state.signOutReason == null) return;
    state = ApiAccessState(ipAccessDenied: state.ipAccessDenied);
  }

  Future<void> signOutFromIpAccessDenied() async {
    state = ApiAccessState(signOutReason: state.signOutReason);
    await _ref.read(authProvider.notifier).signOut();
  }

  void reset() {
    _forcedSignOutFuture = null;
    state = ApiAccessState.empty;
  }
}

final apiAccessProvider =
    StateNotifierProvider<ApiAccessNotifier, ApiAccessState>((ref) {
      return ApiAccessNotifier(ref);
    });
