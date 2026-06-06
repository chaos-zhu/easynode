import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/features/shell/editor/editor_language.dart';
import 'package:easynode_native/features/shell/editor/text_editor_controller.dart';

class _FakeWriter implements TextEditorWriter {
  _FakeWriter({this.shouldThrow = false});
  bool shouldThrow;
  String? lastWritten;
  int writes = 0;

  @override
  Future<void> writeTextFile(String remotePath, String content) async {
    writes++;
    if (shouldThrow) throw Exception('boom');
    lastWritten = content;
  }
}

void main() {
  group('TextEditorController', () {
    test('starts clean and becomes dirty on edit', () {
      final controller = TextEditorController(
        writer: _FakeWriter(),
        remotePath: '/etc/app.json',
        originalText: '{"a":1}',
        language: detectFromFileName('app.json'),
        totalBytes: 7,
      );

      expect(controller.isDirty, isFalse);
      controller.code.text = '{"a":2}';
      expect(controller.isDirty, isTrue);
      controller.dispose();
    });

    test('save persists content and resets isDirty on success', () async {
      final writer = _FakeWriter();
      final controller = TextEditorController(
        writer: writer,
        remotePath: '/etc/app.json',
        originalText: '{"a":1}',
        language: detectFromFileName('app.json'),
        totalBytes: 7,
      );
      controller.code.text = '{"a":2}';
      await controller.save();
      expect(writer.lastWritten, '{"a":2}');
      expect(controller.isDirty, isFalse);
      controller.dispose();
    });

    test('save failure keeps isDirty true and rethrows', () async {
      final writer = _FakeWriter(shouldThrow: true);
      final controller = TextEditorController(
        writer: writer,
        remotePath: '/etc/app.json',
        originalText: '{"a":1}',
        language: detectFromFileName('app.json'),
        totalBytes: 7,
      );
      controller.code.text = '{"a":2}';
      await expectLater(controller.save(), throwsException);
      expect(controller.isDirty, isTrue);
      controller.dispose();
    });
  });
}
