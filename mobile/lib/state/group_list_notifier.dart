import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/servers/server_group_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

/// Mirrors web's `store.groupList` + `store.getGroupList()`.
class GroupListNotifier extends AsyncNotifier<List<ServerGroupModel>> {
  @override
  Future<List<ServerGroupModel>> build() async {
    final repo = ref.watch(serverRepositoryProvider);
    try {
      return await repo.fetchGroups();
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
        return await ref.read(serverRepositoryProvider).fetchGroups();
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

final groupListProvider =
    AsyncNotifierProvider<GroupListNotifier, List<ServerGroupModel>>(
  GroupListNotifier.new,
);
