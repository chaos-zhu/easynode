import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/models/plus_info.dart';
import 'api_providers.dart';

/// Mirrors web's `/plus-discount` polling — optional banner/announcement.
/// Errors silently degrade to "no discount" so the bell can still open.
class PlusDiscountNotifier extends AsyncNotifier<PlusDiscount> {
  @override
  Future<PlusDiscount> build() async {
    return ref.watch(settingsRepositoryProvider).getPlusDiscount();
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    try {
      state = AsyncData(
        await ref.read(settingsRepositoryProvider).getPlusDiscount(),
      );
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }
}

final plusDiscountProvider =
    AsyncNotifierProvider<PlusDiscountNotifier, PlusDiscount>(
      PlusDiscountNotifier.new,
    );
