import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/servers/server_model.dart';
import 'api_providers.dart';

/// Mirrors web's `store.hostList` + `store.getHostList()`: the list is fetched
/// on first read and exposed as an [AsyncValue] so the UI can show
/// loading / error / data without manual `_loading` flags.
class HostListNotifier extends AsyncNotifier<List<ServerModel>> {
  @override
  Future<List<ServerModel>> build() async {
    final repo = ref.watch(serverRepositoryProvider);
    return repo.fetchHosts();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final hosts = await ref.read(serverRepositoryProvider).fetchHosts();
      state = AsyncData(hosts);
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }
}

final hostListProvider =
    AsyncNotifierProvider<HostListNotifier, List<ServerModel>>(
  HostListNotifier.new,
);
