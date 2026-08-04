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
}
