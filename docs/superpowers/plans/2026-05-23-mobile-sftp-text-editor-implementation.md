# Mobile SFTP Text File Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let mobile SFTP users single-tap a text file to open a full-screen editor with syntax highlighting, line numbers, undo/redo, language-aware formatting (JSON/YAML/XML), and save-back-to-remote, with size and binary-file guards.

**Architecture:** Pure client-side, no backend change. Add a `mobile/lib/features/shell/editor/` package with four focused units (sniffer, language detector, formatters, controller) plus a `TextEditorPage` that hosts the third-party `re_editor` widget. `SftpSessionManager` gains `readTextFile` / `writeTextFile` helpers that wrap existing `_readRemoteFile` / `_writeRemoteFile` with size-stat and NUL-byte gates, and two typed exceptions so the UI can branch on them. `_SftpFileRow.onTap` in `sftp_tab.dart` becomes the single entry point: tap a file → call `readTextFile` → on success `Navigator.push` the editor, on the two typed exceptions toast localized errors.

**Tech Stack:** Flutter / Dart `^3.11.5`, `re_editor` + `re_highlight` (Reqable, MIT), `yaml ^3.1.2`, `xml ^6.5.0`, existing `dartssh2 ^2.12.0` + `flutter_riverpod`. Spec reference: `docs/superpowers/specs/2026-05-23-mobile-sftp-text-editor-design.md`. Per `CLAUDE.md` the mobile workflow runs `flutter analyze` only — tests are written but not auto-run.

---

## File Structure

- Modify: `mobile/pubspec.yaml`
  - Add `re_editor`, `re_highlight`, `yaml ^3.1.2`, `xml ^6.5.0` under `dependencies`.
- Create: `mobile/lib/features/shell/editor/editor_text_sniffer.dart`
  - `TextSniffResult` data class + `sniffAndDecode(Uint8List bytes)` returning binary flag, malformedUtf8 flag, and decoded text.
- Create: `mobile/test/features/shell/editor/editor_text_sniffer_test.dart`
  - Cover NUL-sniff window, pure ASCII, valid UTF-8 multibyte, malformed UTF-8 fallback, empty input.
- Create: `mobile/lib/features/shell/editor/editor_language.dart`
  - `EditorLanguage` data class + `detectFromFileName(String name)` returning id / `re_highlight` Mode / formatSupported / defaultIndent.
- Create: `mobile/test/features/shell/editor/editor_language_test.dart`
  - Cover .json / .yaml / .xml / .yml / .ts / .sh / unknown extension / no extension.
- Create: `mobile/lib/features/shell/editor/editor_formatters.dart`
  - `formatJson`, `formatYaml`, `formatXml`; throws `FormatException` on parse failure.
- Create: `mobile/test/features/shell/editor/editor_formatters_test.dart`
  - Cover valid + malformed input for each formatter.
- Modify: `mobile/lib/features/shell/sftp_session_manager.dart`
  - Add `SftpFileTooLargeException`, `SftpBinaryFileException`, `readTextFile`, `writeTextFile`.
- Create: `mobile/test/features/shell/sftp_session_manager_text_test.dart`
  - Sanity-check that the two exception classes carry their fields and that `readTextFile`'s size limit constant matches the spec (lightweight, no real SSH).
- Create: `mobile/lib/features/shell/editor/text_editor_controller.dart`
  - `ChangeNotifier` holding `CodeLineEditingController code`, `_originalText`, `_saving`, `isDirty`, `save()`, `format()`.
- Create: `mobile/test/features/shell/editor/text_editor_controller_test.dart`
  - Fake `SftpSessionManager` covering: isDirty on edit, save updates baseline, save failure preserves isDirty, format rewrites text, format on unsupported language no-ops.
- Create: `mobile/lib/features/shell/editor/text_editor_page.dart`
  - `StatefulWidget`: AppBar + MetaBar + `CodeEditor` + StatusBar + ActionBar; `PopScope` unsaved guard.
- Modify: `mobile/lib/l10n/strings_en.dart`
  - Append `editor.*` keys before closing `};`.
- Modify: `mobile/lib/l10n/strings_zh.dart`
  - Same keys with zh text.
- Modify: `mobile/lib/features/shell/sftp_tab.dart`
  - Replace `_SftpFileRow.onTap` non-directory branch (currently no-op) with `_openInEditor(session, entry)`; add the handler near `_showFileActionSheet`.

---

## Task 1: Add Dependencies and Skeleton Directory

**Files:**
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/features/shell/editor/.gitkeep` (only if dir-as-empty; otherwise skip — Task 2 creates the first file)

- [ ] **Step 1: Add packages via pub**

Run from `mobile/`:

```
flutter pub add re_editor re_highlight yaml:^3.1.2 xml:^6.5.0
```

Expected: `pubspec.yaml` gets four new entries and `pubspec.lock` updates. Note the caret ranges that pub picks for `re_editor` and `re_highlight` (they are 0.x).

- [ ] **Step 2: Verify pubspec block**

Open `mobile/pubspec.yaml`. The `dependencies:` block should now contain (in addition to existing lines):

```yaml
  re_editor: ^<version chosen by pub>
  re_highlight: ^<version chosen by pub>
  yaml: ^3.1.2
  xml: ^6.5.0
```

If pub chose a `^0.x` caret for `re_editor` or `re_highlight`, leave it as-is — that matches the spec note.

- [ ] **Step 3: Sanity build**

Run from `mobile/`:

```
flutter pub get
flutter analyze
```

Expected: no new errors. Pre-existing analyzer output is untouched.

- [ ] **Step 4: Commit**

```
git add mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "feat(mobile): 新增 re_editor / yaml / xml 依赖，准备 SFTP 文本编辑器"
```

---

## Task 2: Text Sniffer Module

**Files:**
- Create: `mobile/lib/features/shell/editor/editor_text_sniffer.dart`
- Test: `mobile/test/features/shell/editor/editor_text_sniffer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/shell/editor/editor_text_sniffer_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_text_sniffer.dart';

void main() {
  group('sniffAndDecode', () {
    test('returns plain text for ASCII bytes', () {
      final result = sniffAndDecode(Uint8List.fromList(utf8.encode('hello\nworld')));
      expect(result.isBinary, isFalse);
      expect(result.malformedUtf8, isFalse);
      expect(result.text, 'hello\nworld');
    });

    test('detects binary when NUL byte appears in first 8 KB', () {
      final bytes = Uint8List.fromList([0x68, 0x69, 0x00, 0x21]);
      final result = sniffAndDecode(bytes);
      expect(result.isBinary, isTrue);
      expect(result.text, '');
    });

    test('only inspects first 8 KB for NUL', () {
      final builder = BytesBuilder()
        ..add(Uint8List(8192))
        ..addByte(0); // NUL just past the 8 KB window
      final bytes = builder.toBytes();
      // Replace the first 8 KB with non-NUL ASCII spaces.
      for (var i = 0; i < 8192; i++) {
        bytes[i] = 0x20;
      }
      final result = sniffAndDecode(bytes);
      expect(result.isBinary, isFalse);
    });

    test('handles valid multibyte UTF-8 without flagging malformed', () {
      final result = sniffAndDecode(Uint8List.fromList(utf8.encode('你好 hello 🌐')));
      expect(result.isBinary, isFalse);
      expect(result.malformedUtf8, isFalse);
      expect(result.text, '你好 hello 🌐');
    });

    test('flags malformedUtf8 but still decodes via allowMalformed', () {
      final bytes = Uint8List.fromList([0x68, 0xC3, 0x28, 0x69]); // invalid UTF-8
      final result = sniffAndDecode(bytes);
      expect(result.isBinary, isFalse);
      expect(result.malformedUtf8, isTrue);
      expect(result.text, isNotEmpty);
    });

    test('empty input is treated as plain text', () {
      final result = sniffAndDecode(Uint8List(0));
      expect(result.isBinary, isFalse);
      expect(result.malformedUtf8, isFalse);
      expect(result.text, '');
    });
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `mobile/lib/features/shell/editor/editor_text_sniffer.dart`:

```dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class TextSniffResult {
  const TextSniffResult({
    required this.isBinary,
    required this.malformedUtf8,
    required this.text,
  });

  final bool isBinary;
  final bool malformedUtf8;
  final String text;
}

TextSniffResult sniffAndDecode(Uint8List bytes) {
  final probeLen = math.min(8192, bytes.length);
  for (var i = 0; i < probeLen; i++) {
    if (bytes[i] == 0) {
      return const TextSniffResult(
        isBinary: true,
        malformedUtf8: false,
        text: '',
      );
    }
  }

  var malformed = false;
  try {
    utf8.decode(bytes);
  } on FormatException {
    malformed = true;
  }

  final text = utf8.decode(bytes, allowMalformed: true);
  return TextSniffResult(
    isBinary: false,
    malformedUtf8: malformed,
    text: text,
  );
}
```

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors in the new files.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/editor/editor_text_sniffer.dart mobile/test/features/shell/editor/editor_text_sniffer_test.dart
git commit -m "feat(mobile): 新增 editor_text_sniffer 二进制与 UTF-8 嗅探"
```

---

## Task 3: Language Detection Module

**Files:**
- Create: `mobile/lib/features/shell/editor/editor_language.dart`
- Test: `mobile/test/features/shell/editor/editor_language_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/shell/editor/editor_language_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_language.dart';

void main() {
  group('detectFromFileName', () {
    test('maps .json to JSON with formatter and highlight', () {
      final lang = detectFromFileName('config.json');
      expect(lang.id, 'JSON');
      expect(lang.formatSupported, isTrue);
      expect(lang.highlightMode, isNotNull);
      expect(lang.defaultIndent, 2);
    });

    test('maps .yaml and .yml to YAML', () {
      expect(detectFromFileName('a.yaml').id, 'YAML');
      expect(detectFromFileName('a.yml').id, 'YAML');
      expect(detectFromFileName('a.yaml').formatSupported, isTrue);
    });

    test('maps .xml to XML', () {
      final lang = detectFromFileName('pom.xml');
      expect(lang.id, 'XML');
      expect(lang.formatSupported, isTrue);
    });

    test('maps .ts to TypeScript without formatter support', () {
      final lang = detectFromFileName('app.ts');
      expect(lang.id, 'TypeScript');
      expect(lang.formatSupported, isFalse);
      expect(lang.highlightMode, isNotNull);
    });

    test('maps .sh to Bash without formatter support', () {
      final lang = detectFromFileName('deploy.sh');
      expect(lang.id, 'Bash');
      expect(lang.formatSupported, isFalse);
    });

    test('unknown extension falls back to plaintext with no highlight', () {
      final lang = detectFromFileName('notes.unknownext');
      expect(lang.id, 'Plain Text');
      expect(lang.formatSupported, isFalse);
      expect(lang.highlightMode, isNull);
    });

    test('file without extension falls back to plaintext', () {
      final lang = detectFromFileName('README');
      expect(lang.id, 'Plain Text');
      expect(lang.highlightMode, isNull);
    });

    test('is case-insensitive on extension', () {
      expect(detectFromFileName('UPPER.JSON').id, 'JSON');
    });
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `mobile/lib/features/shell/editor/editor_language.dart`:

```dart
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/nginx.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

class EditorLanguage {
  const EditorLanguage({
    required this.id,
    required this.highlightMode,
    required this.formatSupported,
    required this.defaultIndent,
  });

  final String id;
  final Mode? highlightMode;
  final bool formatSupported;
  final int defaultIndent;
}

const _plainText = EditorLanguage(
  id: 'Plain Text',
  highlightMode: null,
  formatSupported: false,
  defaultIndent: 2,
);

EditorLanguage detectFromFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return _plainText;
  }
  final ext = name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'json':
      return EditorLanguage(
        id: 'JSON',
        highlightMode: langJson,
        formatSupported: true,
        defaultIndent: 2,
      );
    case 'yaml':
    case 'yml':
      return EditorLanguage(
        id: 'YAML',
        highlightMode: langYaml,
        formatSupported: true,
        defaultIndent: 2,
      );
    case 'xml':
    case 'html':
    case 'htm':
    case 'svg':
      return EditorLanguage(
        id: 'XML',
        highlightMode: langXml,
        formatSupported: ext == 'xml',
        defaultIndent: 2,
      );
    case 'ts':
    case 'tsx':
      return EditorLanguage(
        id: 'TypeScript',
        highlightMode: langTypescript,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'js':
    case 'jsx':
    case 'mjs':
    case 'cjs':
      return EditorLanguage(
        id: 'JavaScript',
        highlightMode: langJavascript,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'sh':
    case 'bash':
    case 'zsh':
      return EditorLanguage(
        id: 'Bash',
        highlightMode: langBash,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'py':
      return EditorLanguage(
        id: 'Python',
        highlightMode: langPython,
        formatSupported: false,
        defaultIndent: 4,
      );
    case 'go':
      return EditorLanguage(
        id: 'Go',
        highlightMode: langGo,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'sql':
      return EditorLanguage(
        id: 'SQL',
        highlightMode: langSql,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'dart':
      return EditorLanguage(
        id: 'Dart',
        highlightMode: langDart,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'md':
    case 'markdown':
      return EditorLanguage(
        id: 'Markdown',
        highlightMode: langMarkdown,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'ini':
    case 'conf':
    case 'cfg':
    case 'toml':
      return EditorLanguage(
        id: 'INI',
        highlightMode: langIni,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'dockerfile':
      return EditorLanguage(
        id: 'Dockerfile',
        highlightMode: langDockerfile,
        formatSupported: false,
        defaultIndent: 2,
      );
    case 'nginx':
      return EditorLanguage(
        id: 'Nginx',
        highlightMode: langNginx,
        formatSupported: false,
        defaultIndent: 2,
      );
    default:
      return _plainText;
  }
}
```

Note: if any of the `re_highlight` language import paths fail to resolve, check the installed version's `lib/languages/` directory and use the actual path. The list mirrors web's `text-editor` mapping; we only need the highlight Modes that ship with the version pub picked.

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors. If any imported language file is missing in the installed `re_highlight` version, remove that case branch and the import line — those languages fall back to `_plainText`.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/editor/editor_language.dart mobile/test/features/shell/editor/editor_language_test.dart
git commit -m "feat(mobile): 新增 editor_language 按文件名识别语言与高亮"
```

---

## Task 4: Formatter Module

**Files:**
- Create: `mobile/lib/features/shell/editor/editor_formatters.dart`
- Test: `mobile/test/features/shell/editor/editor_formatters_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/shell/editor/editor_formatters_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_formatters.dart';

void main() {
  group('formatJson', () {
    test('pretty-prints with 2-space indent', () {
      final out = formatJson('{"a":1,"b":[1,2,3]}');
      expect(out, contains('\n  "a": 1'));
      expect(out, contains('    1'));
    });

    test('throws FormatException on invalid JSON', () {
      expect(() => formatJson('{not json'), throwsA(isA<FormatException>()));
    });
  });

  group('formatYaml', () {
    test('round-trips a simple map with 2-space indent', () {
      final out = formatYaml('foo: 1\nbar:\n  baz: hello');
      expect(out, contains('foo: 1'));
      expect(out, contains('bar:'));
      expect(out, contains('  baz: hello'));
    });

    test('throws FormatException on invalid YAML', () {
      expect(() => formatYaml(': : : not yaml'), throwsA(isA<FormatException>()));
    });
  });

  group('formatXml', () {
    test('pretty-prints valid xml with 2-space indent', () {
      final out = formatXml('<a><b>x</b></a>');
      expect(out, contains('<a>'));
      expect(out, contains('  <b>x</b>'));
    });

    test('throws FormatException on invalid XML', () {
      expect(() => formatXml('<a><b></a>'), throwsA(isA<FormatException>()));
    });
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `mobile/lib/features/shell/editor/editor_formatters.dart`:

```dart
import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

String formatJson(String src) {
  try {
    final decoded = jsonDecode(src);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException {
    rethrow;
  }
}

String formatYaml(String src) {
  try {
    final decoded = loadYaml(src);
    final buffer = StringBuffer();
    _dumpYaml(decoded, buffer, 0);
    final output = buffer.toString();
    return output.endsWith('\n') ? output : '$output\n';
  } on YamlException catch (err) {
    throw FormatException(err.message);
  }
}

String formatXml(String src) {
  try {
    final doc = XmlDocument.parse(src);
    return doc.toXmlString(pretty: true, indent: '  ');
  } on XmlException catch (err) {
    throw FormatException(err.message);
  }
}

void _dumpYaml(dynamic node, StringBuffer buf, int indent) {
  final pad = '  ' * indent;
  if (node is YamlMap || node is Map) {
    final map = node is YamlMap
        ? node.nodes.map((k, v) => MapEntry(k.toString(), v.value))
        : (node as Map);
    if (map.isEmpty) {
      buf.write('{}\n');
      return;
    }
    var first = true;
    for (final entry in map.entries) {
      if (!first || indent > 0) buf.write(pad);
      first = false;
      buf.write('${_yamlKey(entry.key.toString())}:');
      final v = entry.value;
      if (v is YamlMap || v is Map || v is YamlList || v is List) {
        buf.write('\n');
        _dumpYaml(v, buf, indent + 1);
      } else {
        buf.write(' ${_yamlScalar(v)}\n');
      }
    }
  } else if (node is YamlList || node is List) {
    final list = node is YamlList ? node.toList() : (node as List);
    if (list.isEmpty) {
      buf.write('$pad[]\n');
      return;
    }
    for (final item in list) {
      buf.write('$pad- ');
      if (item is YamlMap || item is Map || item is YamlList || item is List) {
        buf.write('\n');
        _dumpYaml(item, buf, indent + 1);
      } else {
        buf.write('${_yamlScalar(item)}\n');
      }
    }
  } else {
    buf.write('$pad${_yamlScalar(node)}\n');
  }
}

String _yamlKey(String key) {
  if (RegExp(r'^[A-Za-z_][\w\-]*$').hasMatch(key)) return key;
  return _yamlQuote(key);
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  final s = value.toString();
  if (s.isEmpty) return '""';
  if (RegExp(r'^(true|false|null|~|\d|-)').hasMatch(s) || s.contains(': ') || s.contains('#')) {
    return _yamlQuote(s);
  }
  return s;
}

String _yamlQuote(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}
```

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/editor/editor_formatters.dart mobile/test/features/shell/editor/editor_formatters_test.dart
git commit -m "feat(mobile): 新增 editor_formatters JSON/YAML/XML 格式化"
```

---

## Task 5: SftpSessionManager Read/Write Text Helpers

**Files:**
- Modify: `mobile/lib/features/shell/sftp_session_manager.dart`
- Test: `mobile/test/features/shell/sftp_session_manager_text_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/shell/sftp_session_manager_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/sftp_session_manager.dart';

void main() {
  group('Sftp text exceptions', () {
    test('SftpFileTooLargeException carries size info', () {
      final err = SftpFileTooLargeException(
        path: '/tmp/big.log',
        size: 5 * 1024 * 1024,
        limit: 2 * 1024 * 1024,
      );
      expect(err.path, '/tmp/big.log');
      expect(err.size, 5 * 1024 * 1024);
      expect(err.limit, 2 * 1024 * 1024);
      expect(err.toString(), contains('big.log'));
    });

    test('SftpBinaryFileException carries path', () {
      final err = SftpBinaryFileException(path: '/usr/bin/ls');
      expect(err.path, '/usr/bin/ls');
      expect(err.toString(), contains('ls'));
    });
  });
}
```

- [ ] **Step 2: Add exceptions and helpers**

Open `mobile/lib/features/shell/sftp_session_manager.dart`. At the bottom of the file (after the existing `class _SftpConnection` block) append:

```dart
class SftpFileTooLargeException implements Exception {
  SftpFileTooLargeException({
    required this.path,
    required this.size,
    required this.limit,
  });

  final String path;
  final int size;
  final int limit;

  @override
  String toString() => 'SftpFileTooLargeException($path, size=$size, limit=$limit)';
}

class SftpBinaryFileException implements Exception {
  SftpBinaryFileException({required this.path});

  final String path;

  @override
  String toString() => 'SftpBinaryFileException($path)';
}

class SftpTextFileData {
  const SftpTextFileData({
    required this.bytes,
    required this.malformedUtf8,
  });

  final Uint8List bytes;
  final bool malformedUtf8;
}
```

Then inside `class SftpSessionManager`, just below the existing `downloadFileBytes` method (around line 347), add:

```dart
  static const int defaultTextFileMaxBytes = 2 * 1024 * 1024;

  Future<Uint8List> readTextFile(
    String remotePath, {
    int maxBytes = defaultTextFileMaxBytes,
  }) async {
    final state = activeSession;
    if (state == null) {
      throw StateError('No active SFTP session');
    }
    final connection = _connections[state.server.id];
    if (connection == null) {
      throw StateError('No active SFTP connection');
    }
    final sftp = connection.sftp;
    final stat = await sftp.stat(remotePath);
    final size = stat.size ?? 0;
    if (size > maxBytes) {
      throw SftpFileTooLargeException(
        path: remotePath,
        size: size,
        limit: maxBytes,
      );
    }
    final bytes = await _readRemoteFile(sftp, remotePath);
    final probeLen = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < probeLen; i++) {
      if (bytes[i] == 0) {
        throw SftpBinaryFileException(path: remotePath);
      }
    }
    return bytes;
  }

  Future<void> writeTextFile(String remotePath, String content) async {
    final state = activeSession;
    if (state == null) {
      throw StateError('No active SFTP session');
    }
    final connection = _connections[state.server.id];
    if (connection == null) {
      throw StateError('No active SFTP connection');
    }
    await _writeRemoteFile(
      connection.sftp,
      remotePath,
      Uint8List.fromList(utf8.encode(content)),
    );
  }
```

If `dart:convert` is not yet imported at the top of the file, add it. (`utf8` lives there.)

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/sftp_session_manager.dart mobile/test/features/shell/sftp_session_manager_text_test.dart
git commit -m "feat(mobile): SftpSessionManager 新增 readTextFile/writeTextFile 与异常类型"
```

---

## Task 6: TextEditorController

**Files:**
- Create: `mobile/lib/features/shell/editor/text_editor_controller.dart`
- Test: `mobile/test/features/shell/editor/text_editor_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/shell/editor/text_editor_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/shell/editor/editor_language.dart';
import 'package:mobile/features/shell/editor/text_editor_controller.dart';

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

    test('format applies JSON formatter when supported', () {
      final controller = TextEditorController(
        writer: _FakeWriter(),
        remotePath: '/etc/app.json',
        originalText: '{"a":1,"b":2}',
        language: detectFromFileName('app.json'),
        totalBytes: 14,
      );
      controller.code.text = '{"a":1,"b":2}';
      controller.format();
      expect(controller.code.text, contains('\n  "a": 1'));
      controller.dispose();
    });

    test('canFormat is false for plaintext', () {
      final controller = TextEditorController(
        writer: _FakeWriter(),
        remotePath: '/etc/notes',
        originalText: 'plain',
        language: detectFromFileName('notes'),
        totalBytes: 5,
      );
      expect(controller.canFormat, isFalse);
      controller.dispose();
    });
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `mobile/lib/features/shell/editor/text_editor_controller.dart`:

```dart
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
        _originalText = originalText,
        code = CodeLineEditingController.fromText(originalText) {
    code.addListener(_onCodeChanged);
  }

  final TextEditorWriter _writer;
  final String remotePath;
  final EditorLanguage language;
  final int totalBytes;
  final CodeLineEditingController code;

  String _originalText;
  bool _saving = false;
  String? _lastError;

  bool get isDirty => code.text != _originalText;
  bool get saving => _saving;
  bool get canFormat => language.formatSupported;
  String? get lastError => _lastError;

  void _onCodeChanged() {
    notifyListeners();
  }

  Future<void> save() async {
    if (_saving) return;
    _saving = true;
    _lastError = null;
    notifyListeners();
    try {
      final content = code.text;
      await _writer.writeTextFile(remotePath, content);
      _originalText = content;
    } catch (error) {
      _lastError = error.toString();
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
```

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/editor/text_editor_controller.dart mobile/test/features/shell/editor/text_editor_controller_test.dart
git commit -m "feat(mobile): 新增 TextEditorController 协调脏标记/保存/格式化"
```

---

## Task 7: i18n Keys

**Files:**
- Modify: `mobile/lib/l10n/strings_en.dart`
- Modify: `mobile/lib/l10n/strings_zh.dart`

- [ ] **Step 1: Append editor.* keys to English**

In `mobile/lib/l10n/strings_en.dart`, replace the closing `};` (currently at line 205) with the block below — i.e., insert these key/value pairs after `'terminal.status.error': 'Error',` and before `};`:

```dart
  // Editor (mobile SFTP text file)
  'editor.tooLarge': 'File exceeds 2 MB. Download to edit.',
  'editor.binary': 'Binary file is not editable.',
  'editor.readFailed': 'Read failed: {0}',
  'editor.saveFailed': 'Save failed: {0}',
  'editor.saved': 'Saved',
  'editor.unsaved': 'Unsaved',
  'editor.format': 'Format',
  'editor.save': 'Save',
  'editor.discardTitle': 'Discard changes?',
  'editor.discardBody': 'Unsaved edits will be lost. Leave?',
  'editor.discardKeepEditing': 'Keep editing',
  'editor.discardLeave': 'Discard',
  'editor.discardSaveAndLeave': 'Save & leave',
  'editor.malformedUtf8': 'File contains non-UTF-8 bytes; saving may lose some characters.',
  'editor.formatUnsupported': 'Format not supported for this language.',
  'editor.formatFailed': 'Format failed: {0}',
  'editor.statusEncoding': 'UTF-8 · LF · {0}',
  'editor.statusPosition': 'Ln {0}, Col {1}',
  'editor.statusLineCount': '{0} / {1}',
  'editor.statusSpaces': 'Spaces: {0}',
};
```

- [ ] **Step 2: Append the same keys to Chinese**

In `mobile/lib/l10n/strings_zh.dart`, replace the closing `};` (currently at line 194) the same way:

```dart
  // Editor (mobile SFTP 文本文件)
  'editor.tooLarge': '文件超过 2 MB，请下载后再编辑',
  'editor.binary': '二进制文件不支持编辑',
  'editor.readFailed': '读取失败：{0}',
  'editor.saveFailed': '保存失败：{0}',
  'editor.saved': '已保存',
  'editor.unsaved': '未保存',
  'editor.format': '格式化',
  'editor.save': '保存',
  'editor.discardTitle': '放弃修改？',
  'editor.discardBody': '当前修改未保存，确定离开？',
  'editor.discardKeepEditing': '继续编辑',
  'editor.discardLeave': '放弃',
  'editor.discardSaveAndLeave': '保存并退出',
  'editor.malformedUtf8': '文件含非 UTF-8 字节，保存可能丢失部分字符',
  'editor.formatUnsupported': '当前语言不支持格式化',
  'editor.formatFailed': '格式化失败：{0}',
  'editor.statusEncoding': 'UTF-8 · LF · {0}',
  'editor.statusPosition': 'Ln {0}, Col {1}',
  'editor.statusLineCount': '{0} / {1}',
  'editor.statusSpaces': 'Spaces: {0}',
};
```

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```
git add mobile/lib/l10n/strings_en.dart mobile/lib/l10n/strings_zh.dart
git commit -m "feat(mobile): 新增 editor.* 国际化文案"
```

---

## Task 8: TextEditorPage Skeleton (AppBar + MetaBar + Editor + StatusBar)

**Files:**
- Create: `mobile/lib/features/shell/editor/text_editor_page.dart`

- [ ] **Step 1: Create page with AppBar, MetaBar, CodeEditor, StatusBar (no ActionBar yet)**

Create `mobile/lib/features/shell/editor/text_editor_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../../l10n/app_localizations.dart';
import '../sftp_session_manager.dart';
import 'editor_language.dart';
import 'text_editor_controller.dart';

class _EditorPalette {
  static const Color background = Color(0xFF0A0F14);
  static const Color statusBg = Color(0xFF111827);
  static const Color statusBorder = Color(0xFF1F2937);
  static const Color statusText = Color(0xFF9CA3AF);
  static const Color gutter = Color(0xFF4B5563);
  static const Color gutterActive = Color(0xFF9CA3AF);
  static const Color appBarBg = Color(0xFF111827);
}

class _SftpManagerWriter implements TextEditorWriter {
  _SftpManagerWriter(this.manager);
  final SftpSessionManager manager;

  @override
  Future<void> writeTextFile(String remotePath, String content) =>
      manager.writeTextFile(remotePath, content);
}

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({
    super.key,
    required this.manager,
    required this.remotePath,
    required this.fileName,
    required this.initialText,
    required this.malformedUtf8,
    required this.totalBytes,
  });

  final SftpSessionManager manager;
  final String remotePath;
  final String fileName;
  final String initialText;
  final bool malformedUtf8;
  final int totalBytes;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final TextEditorController _controller;
  late final EditorLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = detectFromFileName(widget.fileName);
    _controller = TextEditorController(
      writer: _SftpManagerWriter(widget.manager),
      remotePath: widget.remotePath,
      originalText: widget.initialText,
      language: _language,
      totalBytes: widget.totalBytes,
    );
    if (widget.malformedUtf8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.tr('editor.malformedUtf8'))));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        backgroundColor: _EditorPalette.background,
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            _buildMetaBar(context),
            Expanded(child: _buildEditor()),
            _buildStatusBar(context),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _EditorPalette.appBarBg,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.remotePath,
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: _controller.code.canUndo ? _controller.code.undo : null,
        ),
        IconButton(
          tooltip: 'Redo',
          icon: const Icon(Icons.redo),
          onPressed: _controller.code.canRedo ? _controller.code.redo : null,
        ),
      ],
    );
  }

  Widget _buildMetaBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _EditorPalette.appBarBg,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _EditorPalette.statusBorder,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _language.id,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l.tr('editor.statusEncoding', [_formatBytes(widget.totalBytes)]),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return CodeEditor(
      controller: _controller.code,
      style: CodeEditorStyle(
        codeTheme: _language.highlightMode == null
            ? null
            : CodeHighlightTheme(
                languages: {_language.id: CodeHighlightThemeMode(mode: _language.highlightMode!)},
                theme: atomOneDarkTheme,
              ),
        backgroundColor: _EditorPalette.background,
        textColor: Colors.white,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
              textStyle: const TextStyle(color: _EditorPalette.gutter, fontSize: 12),
              focusedTextStyle: const TextStyle(color: _EditorPalette.gutterActive, fontSize: 12),
            ),
            DefaultCodeChunkIndicator(
              width: 14,
              controller: chunkController,
              notifier: notifier,
            ),
          ],
        );
      },
      chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sel = _controller.code.selection;
    final lineIndex = sel.baseIndex;
    final colIndex = sel.baseOffset;
    final total = _controller.code.codeLines.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: _EditorPalette.statusBg,
        border: Border(top: BorderSide(color: _EditorPalette.statusBorder)),
      ),
      child: Row(
        children: [
          Text(
            l.tr('editor.statusPosition', ['${lineIndex + 1}', '${colIndex + 1}']),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
          const SizedBox(width: 16),
          Text(
            '${_language.id} · ${l.tr('editor.statusSpaces', ['${_language.defaultIndent}'])}',
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
          const Spacer(),
          Text(
            l.tr('editor.statusLineCount', ['${lineIndex + 1}', '$total']),
            style: const TextStyle(fontSize: 11, color: _EditorPalette.statusText),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
```

If `AppLocalizations` is imported from a different path, adjust the import. (See `mobile/lib/features/shell/sftp_tab.dart` for the existing import.)

- [ ] **Step 2: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors. If `DefaultCodeLineNumber` / `DefaultCodeChunkIndicator` / `DefaultCodeChunkAnalyzer` have a different name in the installed `re_editor`, check `re_editor`'s `lib/` exports and adjust.

- [ ] **Step 3: Commit**

```
git add mobile/lib/features/shell/editor/text_editor_page.dart
git commit -m "feat(mobile): 新增 TextEditorPage 骨架与编辑区"
```

---

## Task 9: TextEditorPage Action Bar + Pop Guard

**Files:**
- Modify: `mobile/lib/features/shell/editor/text_editor_page.dart`

- [ ] **Step 1: Add the bottom action bar**

In `text_editor_page.dart`, change the body `Column` children to include the action bar at the bottom, and wrap the `Scaffold` in a `PopScope`. Replace the `Widget build(...)` method body with:

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_controller.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final action = await _showDiscardDialog(context);
        if (!mounted) return;
        if (action == _DiscardAction.discard) {
          Navigator.of(context).pop();
        } else if (action == _DiscardAction.saveAndLeave) {
          try {
            await _controller.save();
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.tr('editor.saved'))));
            if (mounted) Navigator.of(context).pop();
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.tr('editor.saveFailed', [error.toString()]))),
            );
          }
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Scaffold(
          backgroundColor: _EditorPalette.background,
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              _buildMetaBar(context),
              Expanded(child: _buildEditor()),
              _buildStatusBar(context),
              SafeArea(top: false, child: _buildActionBar(context)),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 2: Add `_DiscardAction` enum, dialog, action bar, save/format handlers**

Append inside `_TextEditorPageState` (anywhere before the closing brace) — and add the enum at the bottom of the file:

```dart
  Widget _buildActionBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _EditorPalette.appBarBg,
        border: Border(top: BorderSide(color: _EditorPalette.statusBorder)),
      ),
      child: Row(
        children: [
          if (_controller.isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '• ${l.tr('editor.unsaved')}',
                style: const TextStyle(fontSize: 11, color: Colors.amber),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: Text(l.tr('editor.format')),
            onPressed: _controller.canFormat ? () => _onFormat(context) : null,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _controller.saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 16),
            label: Text(l.tr('editor.save')),
            onPressed:
                (_controller.isDirty && !_controller.saving) ? () => _onSave(context) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _onSave(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      await _controller.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.saved'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('editor.saveFailed', [error.toString()]))),
      );
    }
  }

  void _onFormat(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_controller.canFormat) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.formatUnsupported'))));
      return;
    }
    try {
      _controller.format();
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('editor.formatFailed', [error.message]))),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('editor.formatFailed', [error.toString()]))),
      );
    }
  }

  Future<_DiscardAction?> _showDiscardDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<_DiscardAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('editor.discardTitle')),
        content: Text(l.tr('editor.discardBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.keepEditing),
            child: Text(l.tr('editor.discardKeepEditing')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.discard),
            child: Text(l.tr('editor.discardLeave')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_DiscardAction.saveAndLeave),
            child: Text(l.tr('editor.discardSaveAndLeave')),
          ),
        ],
      ),
    );
  }
}

enum _DiscardAction { keepEditing, discard, saveAndLeave }
```

(Remove the original closing `}` of `_TextEditorPageState` if it ends up duplicated — the appended block already supplies one.)

- [ ] **Step 3: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors. If `Colors.amber.withValues` isn't available on the installed Flutter (older versions used `withOpacity`), switch to `Colors.amber.withOpacity(0.2)`.

- [ ] **Step 4: Commit**

```
git add mobile/lib/features/shell/editor/text_editor_page.dart
git commit -m "feat(mobile): TextEditorPage 接入格式化/保存按钮与 PopScope 未保存拦截"
```

---

## Task 10: Wire Single-Tap Entry from sftp_tab.dart

**Files:**
- Modify: `mobile/lib/features/shell/sftp_tab.dart`

- [ ] **Step 1: Add imports**

Open `mobile/lib/features/shell/sftp_tab.dart`. Near the existing `import` block (alongside the other shell imports), add:

```dart
import 'editor/editor_text_sniffer.dart';
import 'editor/text_editor_page.dart';
```

- [ ] **Step 2: Replace the non-directory branch in `_SftpFileRow.onTap`**

Locate the `onTap` callback that wraps `_SftpFileRow` near line 209. Replace:

```dart
                          onTap: () {
                            if (session.hasSelection) {
                              session.toggleSelection(entry.name);
                            } else if (entry.isDirectory) {
                              manager.openPath(
                                manager.entryPath(session, entry),
                              );
                            }
                          },
```

with:

```dart
                          onTap: () {
                            if (session.hasSelection) {
                              session.toggleSelection(entry.name);
                            } else if (entry.isDirectory) {
                              manager.openPath(
                                manager.entryPath(session, entry),
                              );
                            } else {
                              _openInEditor(context, manager, session, entry);
                            }
                          },
```

- [ ] **Step 3: Add `_openInEditor` handler**

Inside the same `_SftpTabBodyState` (or whatever class owns `_showFileActionSheet`), add this method near `_showFileActionSheet`. If the method is on a stateful widget, you can use `mounted`; otherwise, replace `mounted` checks with `context.mounted`:

```dart
  Future<void> _openInEditor(
    BuildContext context,
    SftpSessionManager manager,
    SftpSessionState session,
    SftpFileEntry entry,
  ) async {
    final l = AppLocalizations.of(context);
    final remotePath = manager.entryPath(session, entry);
    try {
      final bytes = await manager.readTextFile(remotePath);
      if (!context.mounted) return;
      final sniff = sniffAndDecode(bytes);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            manager: manager,
            remotePath: remotePath,
            fileName: entry.name,
            initialText: sniff.text,
            malformedUtf8: sniff.malformedUtf8,
            totalBytes: bytes.length,
          ),
        ),
      );
      if (!context.mounted) return;
      await manager.refreshActive();
    } on SftpFileTooLargeException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.tooLarge'))));
    } on SftpBinaryFileException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.tr('editor.binary'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('editor.readFailed', [error.toString()]))),
      );
    }
  }
```

Make sure `sniffAndDecode` is the import from the new `editor_text_sniffer.dart`. If `SftpFileEntry`, `SftpSessionState`, `SftpSessionManager`, `SftpFileTooLargeException`, `SftpBinaryFileException` are not already in scope at the call site, ensure the existing `import 'sftp_session_manager.dart';` covers them (it does — Task 5 puts all three exception classes in the same file).

- [ ] **Step 4: Run analyzer**

Run from `mobile/`:

```
flutter analyze
```

Expected: no errors. If the analyzer complains about `mounted` on a non-State class, swap to `context.mounted` (already used above).

- [ ] **Step 5: Commit**

```
git add mobile/lib/features/shell/sftp_tab.dart
git commit -m "feat(mobile): SFTP 单击文件进入文本编辑器，分支三类异常 toast"
```

---

## Task 11: Final analyze + manual smoke

**Files:** (none — verification only)

- [ ] **Step 1: Full analyze run**

Run from `mobile/`:

```
flutter pub get
flutter analyze
```

Expected: no errors.

- [ ] **Step 2: Manual smoke list (record results inline if any deviation)**

Connect to a test server in SFTP tab and verify the golden path + edge cases manually:

1. Tap a `.json` file (≤ 2 MB) → editor opens with JSON highlight, line numbers, language chip says `JSON`.
2. Edit one character → action bar shows `• 未保存 / Unsaved`, Save becomes active.
3. Tap `格式化 / Format` → JSON is pretty-printed; isDirty stays true (text changed) or flips to clean if formatted output equals previous saved baseline.
4. Tap `保存 / Save` → toast `已保存 / Saved`; Save button disables.
5. Open a `.yaml` file → YAML highlight; format still works (note: comments are dropped — known limitation).
6. Open a `.xml` file → XML highlight; format works.
7. Open an unknown extension (e.g. `.log`) → plain text, no highlight, format button disabled.
8. Tap a file > 2 MB (e.g. `/var/log/syslog`) → toast `文件超过 2 MB / File exceeds 2 MB`, page does not open.
9. Tap a binary (e.g. `/bin/ls`) → toast `二进制文件不支持编辑 / Binary file is not editable`, page does not open.
10. Edit a file then press the device back button → confirm dialog with three options behaves: keepEditing returns, discard pops without save, saveAndLeave saves then pops; on save error toast appears and page stays.
11. Open a file containing non-UTF-8 byte sequences (e.g., GB18030 text) → page opens with `editor.malformedUtf8` warning toast.

- [ ] **Step 3: Final commit (only if any analyzer cleanup was needed)**

If Steps 1–2 surfaced no follow-up fixes, no commit is needed for this task. Otherwise:

```
git add <files>
git commit -m "chore(mobile): SFTP 编辑器 smoke 修复"
```

---

## Notes for the implementing engineer

- Per `CLAUDE.md`, the mobile workflow runs `flutter analyze` only. The `*_test.dart` files in this plan are written for future regression — do NOT run `flutter test` unless the user explicitly asks for it.
- `.pen` files are encrypted; the design source-of-truth (Pencil node `sYMaF`) was already captured into the spec under `docs/superpowers/specs/2026-05-23-mobile-sftp-text-editor-design.md` §5. Do not try to read the `.pen` file directly — use the spec.
- The web equivalent (`web/src/components/text-editor/index.vue`) is a reference for ext → language mapping. Do not couple the two; mobile is intentionally a smaller surface.
- `re_editor` and `re_highlight` are still 0.x — if pub picks a different version than expected and the API differs, prefer adapting the code (Tasks 6, 8) over downgrading the library, since we want the latest mobile-perf improvements.
- The `_openInEditor` handler is placed inside the same widget that already owns `_showFileActionSheet` so we reuse the same `BuildContext` and `ScaffoldMessenger` pattern (`_showSnack` is a sibling helper if you'd rather use it).
