import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/settings/models/plus_info.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

/// Mirrors web's `store.plusInfo` + `store.getPlusInfo()`.
class PlusInfoNotifier extends AsyncNotifier<PlusInfo> {
  @override
  Future<PlusInfo> build() async {
    try {
      return await ref.watch(settingsRepositoryProvider).getPlusInfo();
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      rethrow;
    }
  }

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        try {
          return await ref.read(settingsRepositoryProvider).getPlusInfo();
        } on UnauthorizedFailure {
          await ref.read(authProvider.notifier).signOut();
          rethrow;
        }
      },
    );
    if (state.hasError && previous != null) state = AsyncData(previous);
  }
}

final plusInfoProvider =
    AsyncNotifierProvider<PlusInfoNotifier, PlusInfo>(PlusInfoNotifier.new);
