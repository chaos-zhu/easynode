import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/servers/server_group_model.dart';
import 'api_providers.dart';

/// Mirrors web's `store.groupList` + `store.getGroupList()`.
class GroupListNotifier extends AsyncNotifier<List<ServerGroupModel>> {
  @override
  Future<List<ServerGroupModel>> build() async {
    final repo = ref.watch(serverRepositoryProvider);
    return repo.fetchGroups();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final groups = await ref.read(serverRepositoryProvider).fetchGroups();
      state = AsyncData(groups);
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }
}

final groupListProvider =
    AsyncNotifierProvider<GroupListNotifier, List<ServerGroupModel>>(
  GroupListNotifier.new,
);
