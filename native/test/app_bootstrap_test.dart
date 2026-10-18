import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/auth/login_page.dart';
import 'package:easynode_native/features/auth/startup_connection_page.dart';
import 'package:easynode_native/features/shell/main_shell_page.dart';

import 'package:easynode_native/app.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StartupApi extends ApiClient {
  _StartupApi()
    : super(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  final attempts = <Completer<void>>[];
  final tokens = <CancelToken>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => {'status': 200, 'data': {}};

  @override
  Future<void> checkSession({required CancelToken cancelToken}) {
    final attempt = Completer<void>();
    attempts.add(attempt);
    tokens.add(cancelToken);
    return attempt.future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'serverAddress': 'http://100.64.0.1:8082',
      'username': 'admin',
      'locale': 'zh',
    });
    FlutterSecureStorage.setMockInitialValues({
      'token': 'saved-token',
      'sessionCookie': 'session=saved-cookie',
      'loginDeviceId': 'saved-device',
    });
    PackageInfo.setMockInitialValues(
      appName: 'EasyNode',
      packageName: 'easynode.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<Widget?> bootstrap(WidgetTester tester, _StartupApi api) =>
      tester.runAsync(
        () => EasyNodeApp.bootstrap(apiClientFactory: (_, {token}) => api),
      );

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(WidgetsApp)));

  testWidgets(
    'offline startup remains on logo and preserves the saved session',
    (tester) async {
      final api = _StartupApi();
      final app = await bootstrap(tester, api);
      expect(api.attempts, isEmpty);
      await tester.pumpWidget(app!);
      await tester.pump();
      final auth = container(tester).read(authProvider);
      expect(auth.signedIn, isTrue);
      expect(auth.publicKeyPem, isNull);
      expect(find.byType(StartupConnectionPage), findsOneWidget);
      expect(find.byType(MainShellPage), findsNothing);
      expect(find.text('正在连接服务器'), findsOneWidget);
      expect(container(tester).read(serverRepositoryProvider), isNotNull);
      expect(container(tester).read(settingsRepositoryProvider), isNotNull);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('连接超时'), findsOneWidget);
      expect(api.tokens.single.isCancelled, isTrue);
      expect(container(tester).read(authProvider).signedIn, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'token'),
        'saved-token',
      );
      expect(find.byType(MainShellPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('successful connection opens home without a fixed logo delay', (
    tester,
  ) async {
    final api = _StartupApi();
    await tester.pumpWidget((await bootstrap(tester, api))!);
    await tester.pump();
    expect(find.byType(MainShellPage), findsNothing);
    api.attempts.single.complete();
    await tester.pump();
    expect(find.byType(MainShellPage), findsOneWidget);
    expect(find.byType(StartupConnectionPage), findsNothing);
    // Let the shell's background update check finish before disposing it.
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('relogin clears authorization and shows login immediately', (
    tester,
  ) async {
    final api = _StartupApi();
    await tester.pumpWidget((await bootstrap(tester, api))!);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(StartupConnectionPage), findsNothing);
    expect(container(tester).read(authProvider).signedIn, isFalse);
    const secure = FlutterSecureStorage();
    for (final key in ['token', 'sessionCookie', 'loginDeviceId']) {
      expect(await secure.read(key: key), isNull);
    }
    // A response from the old attempt cannot reopen home or log out again.
    api.attempts.single.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expired session switches from logo to login', (tester) async {
    final api = _StartupApi();
    await tester.pumpWidget((await bootstrap(tester, api))!);
    await tester.pump();
    api.attempts.single.completeError(
      UnauthorizedFailure('expired', statusCode: 403),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(await const FlutterSecureStorage().read(key: 'token'), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final entry in ['signed out', 'expired session', 'manual relogin']) {
    testWidgets('login after $entry opens home without a startup check', (
      tester,
    ) async {
      if (entry == 'signed out') {
        FlutterSecureStorage.setMockInitialValues({});
      }
      final restoredApi = _StartupApi();
      await tester.pumpWidget((await bootstrap(tester, restoredApi))!);
      await tester.pump();
      if (entry == 'expired session') {
        restoredApi.attempts.single.completeError(
          UnauthorizedFailure('expired', statusCode: 403),
        );
        await tester.pumpAndSettle();
      } else if (entry == 'manual relogin') {
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.text('重新登录'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(LoginPage), findsOneWidget);

      final api = _StartupApi();
      // Publish the authenticated session, as the login success handler does.
      // Check this transition before the handler's later bookkeeping finishes.
      final signIn = container(tester)
          .read(authProvider.notifier)
          .signIn(
            session: const AuthSession(
              serverAddress: 'http://100.64.0.1:8082',
              username: 'admin',
              token: 'new-token',
              deviceId: 'new-device',
            ),
            apiClient: api,
            publicKeyPem: 'test-public-key',
          );
      await signIn;
      await tester.pump();
      expect(api.attempts, isEmpty);
      expect(find.byType(MainShellPage), findsOneWidget);
      expect(find.byType(StartupConnectionPage), findsNothing);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('missing session credentials still opens signed out', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final app = await tester.runAsync(EasyNodeApp.bootstrap);
    await tester.pumpWidget(app!);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WidgetsApp)),
    );
    expect(container.read(authProvider).signedIn, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
