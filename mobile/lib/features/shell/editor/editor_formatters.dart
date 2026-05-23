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
