/// Thrown by `ApiClient` on a non-success HTTP response or a network failure.
/// The message is always the user-presentable string and `statusCode` is the
/// HTTP status from the server if any.
class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode, this.data});

  final String message;
  final int? statusCode;

  /// Raw `data` object from the server response body, if any. Used to surface
  /// structured flags like `needRestart` from `/plus-conf`.
  final Object? data;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  /// `true` when the server signalled the client must restart the panel
  /// service before re-activating Plus (kicked session).
  bool get needRestart {
    final d = data;
    if (d is Map) {
      final v = d['needRestart'];
      return v == true || v == 1 || v == '1' || v == 'true';
    }
    return false;
  }

  @override
  String toString() => message;
}

class UnauthorizedFailure extends ApiFailure {
  UnauthorizedFailure(super.message, {super.statusCode, super.data});
}
