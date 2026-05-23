import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import 'editor_formatters.dart';
import 'editor_language.dart';

abstract class TextEditorWriter {
  Future<void> writeTextFile(String remotePath, String content);
}

class TextEditorController extends ChangeNotifier {
  TextEditorController({
    required TextEditorWriter writer,
    required this.remotePath,
    required String originalText,
    required this.language,
    required this.totalBytes,
  })  : _writer = writer,
        _originalText = '',
        code = CodeLineEditingController.fromText(originalText) {
    _originalText = code.text;
    code.addListener(_onCodeChanged);
  }

  final TextEditorWriter _writer;
  final String remotePath;
  final EditorLanguage language;
  final int totalBytes;
  final CodeLineEditingController code;

  String _originalText;
  bool _saving = false;

  bool get isDirty => code.text != _originalText;
  bool get saving => _saving;
  bool get canFormat => language.formatSupported;

  void _onCodeChanged() {
    notifyListeners();
  }

  Future<void> save() async {
    if (_saving) return;
    _saving = true;
    notifyListeners();
    try {
      final content = code.text;
      await _writer.writeTextFile(remotePath, content);
      _originalText = content;
    } catch (_) {
      rethrow;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void format() {
    if (!language.formatSupported) return;
    final src = code.text;
    final String formatted;
    switch (language.id) {
      case 'JSON':
        formatted = formatJson(src);
        break;
      case 'YAML':
        formatted = formatYaml(src);
        break;
      case 'XML':
        formatted = formatXml(src);
        break;
      default:
        return;
    }
    if (formatted != src) {
      code.text = formatted;
    }
  }

  @override
  void dispose() {
    code.removeListener(_onCodeChanged);
    code.dispose();
    super.dispose();
  }
}
