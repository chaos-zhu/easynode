import 'dart:async';

import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:easynode_native/state/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowCookieStorage extends SecureAppStorage {
  _SlowCookieStorage() : super(const FlutterSecureStorage());

  final cookieDeleteStarted = Completer<void>();
  final releaseCookieDelete = Completer<void>();
  final deleted = <String>[];

  @override
  Future<void> deleteToken() async => deleted.add('token');

  @override
  Future<void> deleteDeviceId() async => deleted.add('device');

  @override
  Future<void> deleteSessionCookie() async {
    cookieDeleteStarted.complete();
    await releaseCookieDelete.future;
    deleted.add('cookie');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final startup in [true, false]) {
    test(
      startup
          ? 'startup keeps login hidden until authorization deletion finishes'
          : 'active-app sign-out still switches UI before slow cleanup',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = AppStorage(await SharedPreferences.getInstance());
        final secure = _SlowCookieStorage();
        final cookies = SessionCookieStore(secure);
        final initial = AuthState(
          session: const AuthSession(
            serverAddress: 'http://100.64.0.1:8082',
            username: 'admin',
            token: 'saved-token',
            deviceId: 'saved-device',
          ),
          apiClient: ApiClient(
            serverAddress: 'http://100.64.0.1:8082',
            cookieStore: cookies,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            appStorageProvider.overrideWithValue(storage),
            secureStorageProvider.overrideWithValue(secure),
            cookieStoreProvider.overrideWithValue(cookies),
            authProvider.overrideWith((ref) => AuthNotifier(ref, initial)),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(authProvider.notifier);
        final cleanup = startup
            ? notifier.signOutAfterCleanup()
            : notifier.signOut();
        await secure.cookieDeleteStarted.future;
        expect(container.read(authProvider).signedIn, startup);
        expect(secure.deleted, ['token', 'device']);
        secure.releaseCookieDelete.complete();
        await cleanup;
        expect(container.read(authProvider).signedIn, isFalse);
        expect(secure.deleted, ['token', 'device', 'cookie']);
      },
    );
  }
}
