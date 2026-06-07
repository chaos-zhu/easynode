import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/app_update_repository.dart';
import 'package_info_provider.dart';

enum AppUpdateStatus { idle, checking, latest, available, failed }

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.result,
    this.error,
  });

  final AppUpdateStatus status;
  final AppUpdateCheckResult? result;
  final Object? error;

  bool get isChecking => status == AppUpdateStatus.checking;
}

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository();
});

final appUpdateProvider =
    StateNotifierProvider<AppUpdateNotifier, AppUpdateState>((ref) {
      return AppUpdateNotifier(ref);
    });

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  AppUpdateNotifier(this._ref) : super(const AppUpdateState());

  final Ref _ref;

  Future<AppUpdateCheckResult?> check() async {
    if (state.isChecking) return state.result;

    state = const AppUpdateState(status: AppUpdateStatus.checking);
    try {
      final packageInfo = await _ref.read(packageInfoProvider.future);
      final result = await _ref
          .read(appUpdateRepositoryProvider)
          .check(packageInfo);
      state = AppUpdateState(
        status: result.hasUpdate
            ? AppUpdateStatus.available
            : AppUpdateStatus.latest,
        result: result,
      );
      return result;
    } catch (error) {
      state = AppUpdateState(status: AppUpdateStatus.failed, error: error);
      return null;
    }
  }
}
