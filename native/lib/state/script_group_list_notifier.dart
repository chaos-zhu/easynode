import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/scripts/script_group_model.dart';
import 'api_providers.dart';

/// Mirrors web's `store.scriptGroupList` + `store.getScriptGroupList()`.
/// Shared between the scripts list, the edit form (group picker), and the
/// group-management page.
class ScriptGroupListNotifier extends AsyncNotifier<List<ScriptGroupModel>> {
  @override
  Future<List<ScriptGroupModel>> build() async {
    final repo = ref.watch(scriptRepositoryProvider);
    return repo.fetchGroups();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final groups = await ref.read(scriptRepositoryProvider).fetchGroups();
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

final scriptGroupListProvider =
    AsyncNotifierProvider<ScriptGroupListNotifier, List<ScriptGroupModel>>(
      ScriptGroupListNotifier.new,
    );
