import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_result.dart';
import 'cookie_store.dart';

const String _fallbackNativeAppVersion = 'unknown';
const String ipAccessDeniedCode = 'IP_ACCESS_DENIED';

typedef SessionFailureHandler =
    Future<void> Function(ApiSessionFailure failure);

const _sensitiveDebugKeys = <String>{
  'apikey',
  'authorization',
  'cookie',
  'encryptedkey',
  'opnesshkeypassword',
  'password',
  'privatekey',
  'set-cookie',
  'tempkey',
  'token',
};

bool _isSensitiveDebugKey(Object? key) {
  final normalized = key
      .toString()
      .replaceAll(RegExp(r'[-_]'), '')
      .toLowerCase();
  return _sensitiveDebugKeys.contains(normalized) ||
      normalized.endsWith('token') ||
      normalized.contains('password') ||
      normalized.contains('privatekey') ||
      normalized.contains('apikey') ||
      normalized.contains('cookie') ||
      normalized.contains('secret');
}

Object? redactDebugValue(Object? value) {
  if (value is Map) {
    return value.map((key, item) {
      return MapEntry(
        key.toString(),
        _isSensitiveDebugKey(key) ? '<redacted>' : redactDebugValue(item),
      );
    });
  }
  if (value is Iterable) return value.map(redactDebugValue).toList();
  return value;
}

Uri redactDebugUri(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri;
  return uri.replace(
    queryParameters: uri.queryParameters.map(
      (key, value) =>
          MapEntry(key, _isSensitiveDebugKey(key) ? '<redacted>' : value),
    ),
  );
}

bool isIpAccessDeniedResponse(Object? body) {
  if (body is! Map) return false;
  final data = body['data'];
  return data is Map && data['code'] == ipAccessDeniedCode;
}

/// Converts a failed HTTP response into the app's semantic error types.
/// Kept outside [ApiClient] so the server response contract is directly
/// testable without a live secure-storage backend.
ApiFailure apiFailureFromDioException(DioException error) {
  final body = error.response?.data;
  String? msg;
  Object? data;
  if (body is Map && body['msg'] is String) {
    msg = body['msg'] as String;
  }
  if (body is Map) {
    data = body['data'];
  }
  final statusCode = error.response?.statusCode;
  final message = msg ?? error.message ?? 'Network error';
  if (isIpAccessDeniedResponse(body)) {
    return IpAccessDeniedFailure(message, statusCode: statusCode, data: data);
  }
  if (statusCode == 401 || statusCode == 403) {
    return UnauthorizedFailure(message, statusCode: statusCode, data: data);
  }
  return ApiFailure(message, statusCode: statusCode, data: data);
}

String buildNativeUserAgent({String? appVersion}) {
  String clientName;
  if (Platform.isAndroid) {
    clientName = 'Android';
  } else if (Platform.isIOS) {
    clientName = 'iOS';
  } else if (Platform.isMacOS) {
    clientName = 'macOS';
  } else if (Platform.isWindows) {
    clientName = 'Windows';
  } else if (Platform.isLinux) {
    clientName = 'Linux';
  } else {
    clientName = 'Native';
  }
  final sanitizedVersion = Platform.operatingSystemVersion
      .replaceAll('(', '[')
      .replaceAll(')', ']')
      .trim();
  final version = appVersion?.trim().isNotEmpty == true
      ? appVersion!.trim()
      : _fallbackNativeAppVersion;
  return 'EasyNode-$clientName/$version ($sanitizedVersion)';
}

class ApiClient {
  ApiClient({
    required String serverAddress,
    required SessionCookieStore cookieStore,
    String? token,
    SessionFailureHandler? onSessionFailure,
    String? appVersion,
    Dio? dio,
  }) : _cookieStore = cookieStore,
       _token = token,
       _onSessionFailure = onSessionFailure,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$serverAddress/api/v1',
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               headers: {
                 'User-Agent': buildNativeUserAgent(appVersion: appVersion),
               },
             ),
           ) {
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint(
              '[API] ${options.method} ${redactDebugUri(options.uri)} '
              '${redactDebugValue(options.data)}',
              wrapWidth: 1024,
            );
            handler.next(options);
          },
          onResponse: (response, handler) {
            debugPrint(
              '[API] ${response.statusCode} '
              '${redactDebugUri(response.requestOptions.uri)} '
              '${redactDebugValue(response.data)}',
              wrapWidth: 1024,
            );
            handler.next(response);
          },
          onError: (error, handler) {
            debugPrint(
              '[API] ERROR ${redactDebugUri(error.requestOptions.uri)} '
              '${redactDebugValue(error.response?.data)}',
              wrapWidth: 1024,
            );
            handler.next(error);
          },
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
      ),
    );
  }

  final Dio _dio;
  final SessionCookieStore _cookieStore;
  SessionFailureHandler? _onSessionFailure;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  void setOnSessionFailure(SessionFailureHandler? handler) {
    _onSessionFailure = handler;
  }

  Future<String> getPublicKey() async {
    final json = await getJson('/get-pub-pem');
    final data = json['data'];
    if (data is String && data.isNotEmpty) return data;
    throw ApiFailure('Server public key is missing');
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request(() => _dio.get(path, queryParameters: queryParameters));
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    return _request(() => _dio.post(path, data: data));
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    return _request(() => _dio.put(path, data: data));
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    return _request(() => _dio.patch(path, data: data));
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request(() => _dio.delete(path, queryParameters: queryParameters));
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      return _asJson(await send());
    } on DioException catch (error) {
      final failure = apiFailureFromDioException(error);
      if (failure is ApiSessionFailure) {
        final handler = _onSessionFailure;
        if (handler != null) {
          try {
            await handler(failure);
          } catch (_) {
            // A global side effect must never replace the request's semantic
            // failure, otherwise feature-level error handling becomes
            // dependent on cleanup implementation details.
          }
        }
      }
      throw failure;
    }
  }

  Map<String, dynamic> _asJson(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw ApiFailure('Unexpected server response');
  }
}
