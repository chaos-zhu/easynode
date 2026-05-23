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

const Set<String> _binaryExtensions = {
  'exe', 'dll', 'so', 'dylib', 'bin', 'elf', 'o', 'a', 'lib',
  'wasm', 'class', 'pyc', 'pyo', 'jar', 'war', 'ear', 'apk', 'aab', 'ipa',
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'ico', 'webp', 'tiff', 'tif',
  'psd', 'ai', 'sketch', 'fig', 'raw', 'heic', 'heif',
  'zip', 'tar', 'gz', 'tgz', 'bz2', 'tbz2', 'xz', 'txz', '7z', 'rar',
  'lz', 'lz4', 'zst', 'deb', 'rpm', 'pkg', 'msi', 'cab',
  'mp3', 'mp4', 'm4a', 'm4v', 'wav', 'flac', 'ogg', 'opus', 'aac', 'wma',
  'mkv', 'avi', 'mov', 'webm', 'mpg', 'mpeg', 'wmv', 'flv', '3gp',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'odt', 'ods', 'odp',
  'db', 'sqlite', 'sqlite3', 'mdb',
  'iso', 'img', 'dmg', 'vmdk', 'qcow2', 'vhd', 'vhdx',
  'ttf', 'otf', 'woff', 'woff2', 'eot',
};

String? _fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

bool isKnownBinaryExtension(String name) {
  final ext = _fileExtension(name);
  if (ext == null) return false;
  return _binaryExtensions.contains(ext);
}

bool hasFileExtension(String name) => _fileExtension(name) != null;

EditorLanguage detectFromFileName(String name) {
  final ext = _fileExtension(name);
  if (ext == null) {
    return _plainText;
  }
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
