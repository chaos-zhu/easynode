import 'package:dio/dio.dart';
import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _httpFailure(int statusCode, Object body) {
  final requestOptions = RequestOptions(path: '/host-list');
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
