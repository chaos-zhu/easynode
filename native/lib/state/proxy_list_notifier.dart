import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/servers/server_proxy_model.dart';
import 'api_providers.dart';

class ProxyListNotifier extends AsyncNotifier<List<ServerProxyModel>> {
  @override
  Future<List<ServerProxyModel>> build() async {
    return _fetch(ref.watch(apiClientProvider));
  }

  Future<void> refresh({bool throwOnError = false}) async {
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch(ref.read(apiClientProvider)));
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      if (!throwOnError) return;
      rethrow;
    }
  }

  Future<List<ServerProxyModel>> _fetch(ApiClient api) async {
    final response = await api.getJson('/proxy');
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ServerProxyModel.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }
}

final proxyListProvider =
    AsyncNotifierProvider<ProxyListNotifier, List<ServerProxyModel>>(
  ProxyListNotifier.new,
);
