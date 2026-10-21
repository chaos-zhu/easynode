import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/servers/server_list_config.dart';
import '../features/servers/server_list_config_repository.dart';
import 'api_providers.dart';

final serverListConfigRepositoryProvider = Provider<ServerListConfigRepository>(
  (ref) => ApiServerListConfigRepository(ref.watch(apiClientProvider)),
);

/// Only desktop subscribes; mobile keeps its existing presentation preferences.
final desktopServerListConfigProvider =
    AsyncNotifierProvider.autoDispose<
      DesktopServerListConfigNotifier,
      ServerListConfig
    >(DesktopServerListConfigNotifier.new);

class DesktopServerListConfigNotifier
    extends AutoDisposeAsyncNotifier<ServerListConfig> {
  @override
  Future<ServerListConfig> build() =>
      ref.watch(serverListConfigRepositoryProvider).fetch();

  Future<void> save(ServerListConfig config) async {
    await ref.read(serverListConfigRepositoryProvider).save(config);
    state = AsyncData(config);
  }
}
