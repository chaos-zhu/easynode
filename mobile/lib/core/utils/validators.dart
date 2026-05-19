/// Thrown by [normalizeServerAddress] when the input is invalid. Carries an
/// i18n [code] (see [stringsEn] keys) plus a default human-readable [message]
/// for callers that don't localize.
class ServerAddressException extends FormatException {
  const ServerAddressException(this.code, String defaultMessage)
      : super(defaultMessage);

  final String code;
}

class ServerAddressErrorCodes {
  static const invalid = 'login.errInvalidServer';
  static const schemeUnsupported = 'login.errSchemeUnsupported';
}

String normalizeServerAddress(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const ServerAddressException(
      ServerAddressErrorCodes.invalid,
      '请输入有效的服务端地址',
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const ServerAddressException(
      ServerAddressErrorCodes.schemeUnsupported,
      '服务端地址仅支持 http 或 https',
    );
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

bool isHttpAddress(String input) {
  final uri = Uri.tryParse(input.trim());
  return uri?.scheme == 'http';
}
