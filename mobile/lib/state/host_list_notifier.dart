import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/servers/server_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

/// Mirrors web's `store.hostList` + `store.getHostList()`: the list is fetched
/// on first read and exposed as an [AsyncValue] so the UI can show
/// loading / error / data without manual `_loading` flags.
class HostListNotifier extends AsyncNotifier<List<ServerModel>> {
  @override
  Future<List<ServerModel>> build() async {
    final repo = ref.watch(serverRepositoryProvider);
    try {
      return await repo.fetchHosts();
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      rethrow;
    }
  }

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    state = await AsyncValue.guard(() async {
      try {
        return await ref.read(serverRepositoryProvider).fetchHosts();
      } on UnauthorizedFailure {
        await ref.read(authProvider.notifier).signOut();
        rethrow;
      }
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    }
  }
}

final hostListProvider =
    AsyncNotifierProvider<HostListNotifier, List<ServerModel>>(
  HostListNotifier.new,
);
