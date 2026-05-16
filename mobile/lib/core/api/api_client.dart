import 'package:dio/dio.dart';

import 'api_result.dart';
import 'cookie_store.dart';

/// HTTP client for the EasyNode REST API.
///
/// - Uses dio with a fixed `${serverAddress}/api/v1` base.
/// - Reuses the existing token+session auth model: token goes into the `token`
///   header, the session cookie is persisted via [SessionCookieStore].
/// - Wraps non-2xx responses into [ApiFailure] with the server `msg` if any.
class ApiClient {
  ApiClient({
    required String serverAddress,
    required SessionCookieStore cookieStore,
    String? token,
    Dio? dio,
  })  : _cookieStore = cookieStore,
        _token = token,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '$serverAddress/api/v1',
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_token != null && _token!.isNotEmpty) {
          options.headers['token'] = _token;
        }
        final cookie = await _cookieStore.readCookieHeader();
        if (cookie != null && cookie.isNotEmpty) {
          options.headers['Cookie'] = cookie;
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final cookies = response.headers.map['set-cookie'];
        if (cookies != null) {
          await _cookieStore.saveFromSetCookieHeaders(cookies);
        }
        handler.next(response);
      },
    ));
  }

  final Dio _dio;
  final SessionCookieStore _cookieStore;
  String? _token;

  /// Update the in-memory token used by the interceptor without recreating
  /// the client. Useful right after login finishes.
  void setToken(String? token) {
    _token = token;
  }

  Future<String> getPublicKey() async {
    final json = await getJson('/get-pub-pem');
    final data = json['data'];
    if (data is String && data.isNotEmpty) return data;
    throw ApiFailure('未获取到服务端公钥');
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _dio.get(path);
      return _asJson(response);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return _asJson(response);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  Map<String, dynamic> _asJson(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw ApiFailure('服务端返回格式异常');
  }

  ApiFailure _toFailure(DioException error) {
    final body = error.response?.data;
    String? msg;
    if (body is Map && body['msg'] is String) {
      msg = body['msg'] as String;
    }
    return ApiFailure(
      msg ?? error.message ?? '网络错误',
      statusCode: error.response?.statusCode,
    );
  }
}
