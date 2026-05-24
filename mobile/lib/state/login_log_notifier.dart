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

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        return await ref.read(settingsRepositoryProvider).getLoginLog();
      } on UnauthorizedFailure {
        await ref.read(authProvider.notifier).signOut();
        rethrow;
      }
    });
    if (state.hasError && previous != null) state = AsyncData(previous);
  }
}

final loginLogProvider =
    AsyncNotifierProvider<LoginLogNotifier, LoginLogData>(LoginLogNotifier.new);
