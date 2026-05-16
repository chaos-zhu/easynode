/// Thrown by `ApiClient` on a non-success HTTP response or a network failure.
/// The message is always the user-presentable string and `statusCode` is the
/// HTTP status from the server if any.
class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}
