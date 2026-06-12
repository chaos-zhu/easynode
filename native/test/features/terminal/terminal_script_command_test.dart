import 'dart:convert';

import 'package:easynode_native/features/terminal/terminal_script_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain script appends newline for immediate execution', () {
    expect(formatTerminalScriptCommand('uptime', useBase64: false), 'uptime\n');
  });

  test('base64 script wraps normalized content in temp script executor', () {
    final command = formatTerminalScriptCommand(
      'echo hi\r\nprintf "中文"\r',
      useBase64: true,
    );

    expect(command, endsWith('\n'));
    expect(command, contains('mktemp /tmp/easynode-script-XXXXXX.sh'));
    expect(command, contains('base64 -d > "\$tmp_script"'));
    expect(command, contains('bash "\$tmp_script"'));
    expect(command, contains('rm -f "\$tmp_script"'));

    final encoded = RegExp(
      r"printf '%s' '([^']+)'",
    ).firstMatch(command)!.group(1)!;
    expect(utf8.decode(base64Decode(encoded)), 'echo hi\nprintf "中文"\n');
  });
}
