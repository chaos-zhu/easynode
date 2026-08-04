import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/models/login_session.dart';
import 'api_providers.dart';

class LoginLogNotifier extends AsyncNotifier<LoginLogData> {
  @override
  Future<LoginLogData> build() async {
    return ref.watch(settingsRepositoryProvider).getLoginLog();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      final log = await ref.read(settingsRepositoryProvider).getLoginLog();
      state = AsyncData(log);
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
