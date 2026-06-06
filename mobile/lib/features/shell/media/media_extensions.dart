const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'webp',
  'ico',
};

String? _ext(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

bool isImageFileName(String name) {
  final ext = _ext(name);
  return ext != null && _imageExtensions.contains(ext);
}

String? mediaExtension(String name) => _ext(name);
