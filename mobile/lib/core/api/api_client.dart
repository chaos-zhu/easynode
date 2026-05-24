import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_result.dart';
import 'cookie_store.dart';

const String _mobileAppVersion = '0.1.0';

String buildMobileUserAgent() {
  String osName;
  if (Platform.isAndroid) {
    osName = 'Android';
  } else if (Platform.isIOS) {
    osName = 'iOS';
  } else if (Platform.isMacOS) {
    osName = 'macOS';
  } else if (Platform.isWindows) {
    osName = 'Windows';
  } else if (Platform.isLinux) {
    osName = 'Linux';
  } else {
    osName = 'Unknown';
  }
  final sanitizedVersion = Platform.operatingSystemVersion
      .replaceAll('(', '[')
      .replaceAll(')', ']')
      .trim();
  return 'EasyNode-Mobile/$_mobileAppVersion ($osName; $sanitizedVersion)';
}

class ApiClient {
  ApiClient({
    required String serverAddress,
    required SessionCookieStore cookieStore,
    String? token,
    Future<void> Function(String? message)? onUnauthorized,
    Dio? dio,
  }) : _cookieStore = cookieStore,
       _token = token,
       _onUnauthorized = onUnauthorized,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$serverAddress/api/v1',
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               headers: {'User-Agent': buildMobileUserAgent()},
             ),
           ) {
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (object) => debugPrint(object.toString(), wrapWidth: 1024),
        ),
      );
    }
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
        onError: (error, handler) {
          final status = error.response?.statusCode;
          if (status == 401 || status == 403) {
            final cb = _onUnauthorized;
            if (cb != null) {
              final body = error.response?.data;
              String? msg;
              if (body is Map && body['msg'] is String) {
                msg = body['msg'] as String;
              }
              _signOutFuture ??= cb(msg);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionCookieStore _cookieStore;
  Future<void> Function(String? message)? _onUnauthorized;
  Future<void>? _signOutFuture;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  void setOnUnauthorized(Future<void> Function(String? message)? cb) {
    _onUnauthorized = cb;
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

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.put(path, data: data);
      return _asJson(response);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final response = await _dio.delete(path);
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
