import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_result.dart';
import '../features/scripts/script_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

/// Mirrors web's `store.scriptList` + `store.getScriptList()`. The list is
/// fetched on first read and exposed as an [AsyncValue]; consumers across
/// the app (scripts tab, terminal quick-actions, etc.) share the same
/// snapshot — refresh once, every screen sees it.
class ScriptListNotifier extends AsyncNotifier<List<ScriptModel>> {
  @override
  Future<List<ScriptModel>> build() async {
    final repo = ref.watch(scriptRepositoryProvider);
    try {
      return await repo.fetchScripts();
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      rethrow;
    }
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final scripts = await ref.read(scriptRepositoryProvider).fetchScripts();
      state = AsyncData(scripts);
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

final scriptListProvider =
    AsyncNotifierProvider<ScriptListNotifier, List<ScriptModel>>(
      ScriptListNotifier.new,
    );
