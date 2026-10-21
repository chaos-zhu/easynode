import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/servers/server_repository.dart';
import 'api_providers.dart';

/// Desktop reads the catalog without mounting mobile connection providers.
final desktopServerCatalogProvider = FutureProvider.autoDispose<HostCatalog>(
  (ref) => ref.watch(serverRepositoryProvider).fetchCatalog(),
);
