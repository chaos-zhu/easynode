import 'package:dio/dio.dart';

import 'api_result.dart';
import 'cookie_store.dart';

class ApiClient {
  ApiClient({
    required String serverAddress,
    required SessionCookieStore cookieStore,
    String? token,
    Dio? dio,
  }) : _cookieStore = cookieStore,
       _token = token,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$serverAddress/api/v1',
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
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
      ),
    );
  }

  final Dio _dio;
  final SessionCookieStore _cookieStore;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Future<String> getPublicKey() async {
    final json = await getJson('/get-pub-pem');
    final data = json['data'];
    if (data is String && data.isNotEmpty) return data;
    throw ApiFailure('Server public key is missing');
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _dio.get(path);
      return _asJson(response);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
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
    throw ApiFailure('Unexpected server response');
  }

  ApiFailure _toFailure(DioException error) {
    final body = error.response?.data;
    String? msg;
    if (body is Map && body['msg'] is String) {
      msg = body['msg'] as String;
    }
    final statusCode = error.response?.statusCode;
    final message = msg ?? error.message ?? 'Network error';
    if (statusCode == 401 || statusCode == 403) {
      return UnauthorizedFailure(message, statusCode: statusCode);
    }
    return ApiFailure(message, statusCode: statusCode);
  }
}
