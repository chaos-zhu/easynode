import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_result.dart';
import '../features/servers/server_credential_model.dart';
import 'api_providers.dart';
import 'auth_notifier.dart';

class CredentialListNotifier
    extends AsyncNotifier<List<ServerCredentialModel>> {
  @override
  Future<List<ServerCredentialModel>> build() async {
    return _fetch(ref.watch(apiClientProvider));
  }

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetch(ref.read(apiClientProvider)),
    );
    if (state.hasError && previous != null) state = AsyncData(previous);
  }

  Future<List<ServerCredentialModel>> _fetch(ApiClient api) async {
    try {
      final response = await api.getJson('/get-ssh-list');
      final raw = response['data'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ServerCredentialModel.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);
    } on UnauthorizedFailure {
      await ref.read(authProvider.notifier).signOut();
      rethrow;
    }
  }
}

final credentialListProvider = AsyncNotifierProvider<CredentialListNotifier,
    List<ServerCredentialModel>>(
  CredentialListNotifier.new,
);
