import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/cookie_store.dart';
import '../core/storage/app_storage.dart';
import '../core/storage/secure_storage.dart';

/// All four storage providers are bootstrap-only — `EasyNodeApp.bootstrap`
/// constructs the concrete instances once and overrides them on the root
/// `ProviderScope`, so reads always succeed without async work.
final appStorageProvider = Provider<AppStorage>((ref) {
  throw UnimplementedError('appStorageProvider must be overridden');
});

final secureStorageProvider = Provider<SecureAppStorage>((ref) {
  throw UnimplementedError('secureStorageProvider must be overridden');
});

final cookieStoreProvider = Provider<SessionCookieStore>((ref) {
  throw UnimplementedError('cookieStoreProvider must be overridden');
});
