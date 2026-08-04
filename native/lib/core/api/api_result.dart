/// Thrown by `ApiClient` on a non-success HTTP response or a network failure.
/// The message is always the user-presentable string and `statusCode` is the
/// HTTP status from the server if any.
class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode, this.data});

  final String message;
  final int? statusCode;

  /// Raw `data` object from the server response body, if any.
  final Object? data;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Base type for failures that affect the active application session and are
/// handled by the global REST session coordinator.
abstract class ApiSessionFailure extends ApiFailure {
  ApiSessionFailure(super.message, {super.statusCode, super.data});
}

class UnauthorizedFailure extends ApiSessionFailure {
  UnauthorizedFailure(super.message, {super.statusCode, super.data});
}

/// The request reached EasyNode, but its source IP is not permitted by the
/// server's IP allow-list. This is not an authentication failure: credentials
/// remain valid and must not be cleared automatically.
class IpAccessDeniedFailure extends ApiSessionFailure {
  IpAccessDeniedFailure(super.message, {super.statusCode, super.data});

  @override
  bool get isUnauthorized => false;
}
