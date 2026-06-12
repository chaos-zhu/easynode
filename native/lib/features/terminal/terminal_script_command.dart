import 'dart:convert';

String formatTerminalScriptCommand(
  String command, {
  required bool useBase64,
  bool appendNewline = true,
}) {
  if (!useBase64) {
    return appendNewline ? '$command\n' : command;
  }

  final normalized = command.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final encoded = base64Encode(utf8.encode(normalized));
  final wrapped =
      'tmp_script=\$(mktemp /tmp/easynode-script-XXXXXX.sh) && '
      "printf '%s' '$encoded' | base64 -d > \"\$tmp_script\" && "
      'chmod +x "\$tmp_script" && bash "\$tmp_script"; '
      'script_status=\$?; [ -n "\$tmp_script" ] && rm -f "\$tmp_script"; '
      'unset tmp_script';
  return appendNewline ? '$wrapped\n' : wrapped;
}
