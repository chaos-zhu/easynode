import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/scheduled_tasks/scheduled_task_models.dart';
import 'api_providers.dart';

class ScheduledTaskNotifier extends AsyncNotifier<List<ScheduledTask>> {
  @override
  Future<List<ScheduledTask>> build() {
    return ref.watch(scheduledTaskRepositoryProvider).fetchTasks();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      state = AsyncData(
        await ref.read(scheduledTaskRepositoryProvider).fetchTasks(),
      );
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (throwOnError) rethrow;
    }
  }

  Future<void> save(ScheduledTaskFormData form) async {
    final repository = ref.read(scheduledTaskRepositoryProvider);
    if (form.isEdit) {
      await repository.updateTask(form);
    } else {
      await repository.createTask(form);
    }
    await refresh(throwOnError: true);
  }

  Future<void> setEnabled(ScheduledTask task, bool enabled) async {
    final detail = await ref
        .read(scheduledTaskRepositoryProvider)
        .fetchTask(task.id);
    final form = ScheduledTaskFormData.fromTask(detail)..enabled = enabled;
    await ref.read(scheduledTaskRepositoryProvider).updateTask(form);
    await refresh(throwOnError: true);
  }

  Future<void> delete(String id) async {
    await ref.read(scheduledTaskRepositoryProvider).deleteTask(id);
    await refresh(throwOnError: true);
  }
}

final scheduledTaskListProvider =
    AsyncNotifierProvider<ScheduledTaskNotifier, List<ScheduledTask>>(
      ScheduledTaskNotifier.new,
    );
