const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'webp',
  'ico',
};

const Set<String> _videoExtensions = {
  'mp4',
  'm4v',
  'mov',
  'webm',
  'mkv',
  '3gp',
  'ts',
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

bool isVideoFileName(String name) {
  final ext = _ext(name);
  return ext != null && _videoExtensions.contains(ext);
}

String? mediaExtension(String name) => _ext(name);
