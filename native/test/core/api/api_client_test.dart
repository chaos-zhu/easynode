import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _httpFailure(int statusCode, Object body) {
  final requestOptions = RequestOptions(path: '/host-catalog');
  return DioException(
    requestOptions: requestOptions,
    response: Response(
      requestOptions: requestOptions,
      statusCode: statusCode,
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup checks a protected endpoint and leaves auth failure to the page',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'sessionCookie': 'session=saved',
      });
      final dio = Dio();
      var globalFailures = 0;
      var expired = false;
      final api = ApiClient(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        token: 'saved-token',
        dio: dio,
        onSessionFailure: (_) async {
          globalFailures++;
        },
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/mfa2-status');
            expect(options.headers['token'], 'saved-token');
            expect(options.headers['Cookie'], 'session=saved');
            if (expired) {
              handler.reject(_httpFailure(403, {'msg': 'expired'}));
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'status': 200, 'data': false},
                ),
              );
            }
          },
        ),
      );
      await api.checkSession(cancelToken: CancelToken());
      expired = true;
      await expectLater(
        api.checkSession(cancelToken: CancelToken()),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(globalFailures, 0);
    },
  );

  test(
    'timeouts preserve credentials and can retry with the same session',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'sessionCookie': 'session=saved',
      });
      var sessionFailures = 0;
      var offline = true;
      final dio = Dio();
      final api = ApiClient(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        token: 'saved-token',
        dio: dio,
        onSessionFailure: (_) async {
          sessionFailures++;
        },
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.headers['token'], 'saved-token');
            expect(options.headers['Cookie'], 'session=saved');
            if (offline) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': []},
                ),
              );
            }
          },
        ),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          api.getJson('/host-catalog'),
          throwsA(isA<ApiFailure>()),
        );
      }
      offline = false;
      expect((await api.getJson('/host-catalog'))['data'], isEmpty);
      expect(sessionFailures, 0);
      expect(
        await const FlutterSecureStorage().read(key: 'sessionCookie'),
        'session=saved',
      );
    },
  );

  test(
    'public-key reads retry after failure and share successful results',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      var attempts = 0;
      final release = Completer<void>();
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            attempts++;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
              );
              return;
            }
            await release.future;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': 'server-public-key'},
              ),
            );
          },
        ),
      );
      final api = ApiClient(
        serverAddress: 'http://100.64.0.1:8082',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
        dio: dio,
      );
      await expectLater(api.getPublicKey(), throwsA(isA<ApiFailure>()));
      final first = api.getPublicKey();
      final second = api.getPublicKey();
      release.complete();
      expect(await Future.wait([first, second]), [
        'server-public-key',
        'server-public-key',
      ]);
      expect(await api.getPublicKey(), 'server-public-key');
      expect(attempts, 2);
    },
  );

  test('maps the IP allow-list response to a non-auth failure', () {
    final failure = apiFailureFromDioException(
      _httpFailure(403, {
        'msg': '当前 IP 不在白名单中，禁止访问',
        'data': {'code': ipAccessDeniedCode},
      }),
    );

    expect(failure, isA<IpAccessDeniedFailure>());
    expect(failure.isUnauthorized, isFalse);
  });

  test('keeps 401 and ordinary 403 responses as authentication failures', () {
    for (final statusCode in [401, 403]) {
      final failure = apiFailureFromDioException(
        _httpFailure(statusCode, {'msg': 'authentication failed', 'data': {}}),
      );

      expect(failure, isA<UnauthorizedFailure>());
      expect(failure.isUnauthorized, isTrue);
    }
  });

  test('preserves current-IP lockout metadata on a 409 response', () {
    final failure = apiFailureFromDioException(
      _httpFailure(409, {
        'msg': 'current IP is not covered',
        'data': {'code': 'CURRENT_IP_NOT_ALLOWED', 'currentIp': '203.0.113.8'},
      }),
    );

    expect(failure, isA<ApiFailure>());
    expect(failure, isNot(isA<ApiSessionFailure>()));
    expect(failure.statusCode, 409);
    expect((failure.data as Map)['code'], 'CURRENT_IP_NOT_ALLOWED');
    expect((failure.data as Map)['currentIp'], '203.0.113.8');
  });

  test('redacts nested credentials and sensitive query parameters', () {
    final redacted =
        redactDebugValue({
              'apiKey': 'sk-secret',
              'nested': {
                'access_token': 'token-value',
                'password': 'password-value',
                'privateKey': 'private-key-value',
                'model': 'gpt-test',
              },
              'items': [
                {'Cookie': 'session=value'},
              ],
            })
            as Map<String, dynamic>;

    expect(redacted['apiKey'], '<redacted>');
    expect((redacted['nested'] as Map)['access_token'], '<redacted>');
    expect((redacted['nested'] as Map)['password'], '<redacted>');
    expect((redacted['nested'] as Map)['privateKey'], '<redacted>');
    expect((redacted['nested'] as Map)['model'], 'gpt-test');
    expect(((redacted['items'] as List).single as Map)['Cookie'], '<redacted>');

    final uri = redactDebugUri(
      Uri.parse('https://example.com/models?api_key=secret&scope=ops'),
    );
    expect(uri.queryParameters['api_key'], '<redacted>');
    expect(uri.queryParameters['scope'], 'ops');
    expect(uri.toString(), isNot(contains('secret')));
  });
}
