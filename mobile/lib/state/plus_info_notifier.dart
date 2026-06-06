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

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      final plusInfo = await ref.read(settingsRepositoryProvider).getPlusInfo();
      state = AsyncData(plusInfo);
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

final plusInfoProvider =
    AsyncNotifierProvider<PlusInfoNotifier, PlusInfo>(PlusInfoNotifier.new);

/// Derived boolean — `true` only when the loaded record is in-date. Loading
/// or error states are treated as inactive so gating UI fails closed.
final isPlusActiveProvider = Provider<bool>((ref) {
  return ref.watch(plusInfoProvider).valueOrNull?.isActive ?? false;
});
