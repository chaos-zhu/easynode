import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'desktop_ssh_directory.dart';

/// Reads only files explicitly selected by the user. Used by desktop imports.
Future<List<String>?> pickDesktopTextFiles({
  bool privateKey = false,
  bool multiple = false,
}) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: multiple,
    initialDirectory: privateKey ? await getDesktopSshDirectory() : null,
    type: privateKey ? FileType.any : FileType.custom,
    allowedExtensions: privateKey ? null : ['json'],
  );
  if (result == null) return null;
  return Future.wait(
    result.files.map((file) async {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      return utf8.decode(bytes).replaceFirst('\ufeff', '');
    }),
  );
}

Future<void> saveDesktopTextFile(String filename, String text) async {
  final path = await FilePicker.saveFile(fileName: filename);
  if (path != null) await File(path).writeAsString(text);
}
