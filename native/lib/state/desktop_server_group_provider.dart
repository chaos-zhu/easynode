import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/servers/server_group_repository.dart';
import 'api_providers.dart';

final desktopServerGroupRepositoryProvider = Provider<ServerGroupRepository>(
  (ref) => ApiServerGroupRepository(ref.watch(apiClientProvider)),
);
