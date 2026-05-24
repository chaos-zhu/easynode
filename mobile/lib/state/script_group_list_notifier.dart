import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/scripts/script_group_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

/// Mirrors web's `store.scriptGroupList` + `store.getScriptGroupList()`.
/// Shared between the scripts list, the edit form (group picker), and the
/// group-management page.
class ScriptGroupListNotifier extends AsyncNotifier<List<ScriptGroupModel>> {
  @override
  Future<List<ScriptGroupModel>> build() async {
    final repo = ref.watch(scriptRepositoryProvider);
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
        return await ref.read(scriptRepositoryProvider).fetchGroups();
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

final scriptGroupListProvider =
    AsyncNotifierProvider<ScriptGroupListNotifier, List<ScriptGroupModel>>(
      ScriptGroupListNotifier.new,
    );
