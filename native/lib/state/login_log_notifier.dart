import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/settings/models/login_session.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

class LoginLogNotifier extends AsyncNotifier<LoginLogData> {
  @override
  Future<LoginLogData> build() async {
    try {
      return await ref.watch(settingsRepositoryProvider).getLoginLog();
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      rethrow;
    }
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      final log = await ref.read(settingsRepositoryProvider).getLoginLog();
      state = AsyncData(log);
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      if (!throwOnError) return;
      rethrow;
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }
}

final loginLogProvider =
    AsyncNotifierProvider<LoginLogNotifier, LoginLogData>(LoginLogNotifier.new);
