import 'dart:io';

import 'package:flutter/services.dart';

/// Initial location only: private keys are read after the user selects a file.
Future<String?> getDesktopSshDirectory() async {
  String? home;
  if (Platform.isMacOS) {
    try {
      // HOME can point at the app container in a sandboxed macOS build.
      home = await const MethodChannel(
        'easynode/files',
      ).invokeMethod<String>('getHomeDirectory');
    } on MissingPluginException {
      // Allows hot reload against a Runner built before this channel existed.
    }
  }
  home ??= Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) return null;
  final directory = '$home${Platform.pathSeparator}.ssh';
  // Windows' picker rejects nonexistent initial directories. macOS handles the
  // fallback itself, and its panel can navigate outside the app sandbox.
  if (Platform.isWindows && !await Directory(directory).exists()) return null;
  return directory;
}
