import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/scripts/script_model.dart';
import 'api_providers.dart';

/// Mirrors web's `store.scriptList` + `store.getScriptList()`. The list is
/// fetched on first read and exposed as an [AsyncValue]; consumers across
/// the app (scripts tab, terminal quick-actions, etc.) share the same
/// snapshot — refresh once, every screen sees it.
class ScriptListNotifier extends AsyncNotifier<List<ScriptModel>> {
  @override
  Future<List<ScriptModel>> build() async {
    final repo = ref.watch(scriptRepositoryProvider);
    return repo.fetchScripts();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final scripts = await ref.read(scriptRepositoryProvider).fetchScripts();
      state = AsyncData(scripts);
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }
}

final scriptListProvider =
    AsyncNotifierProvider<ScriptListNotifier, List<ScriptModel>>(
      ScriptListNotifier.new,
    );
