String normalizeServerAddress(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('请输入有效的服务端地址');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('服务端地址仅支持 http 或 https');
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

bool isHttpAddress(String input) {
  final uri = Uri.tryParse(input.trim());
  return uri?.scheme == 'http';
}
