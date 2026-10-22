import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Mirrors the Web terminal's command envelope, executed in the current PTY.
/// Random marker lines delimit tool output; they never reach the terminal UI.
class TerminalCommandBridge {
  TerminalCommandBridge({required this.write, required this.display});
  final void Function(String) write;
  final void Function(String) display;
  _Command? _active;
  bool get busy => _active != null;

  Future<Map<String, dynamic>> execute(
    String command,
    String requestId, {
    void Function(Map<String, dynamic>)? onProgress,
    Duration timeout = const Duration(hours: 1),
  }) {
    if (busy) return Future.value({'ok': false, 'error': '当前终端已有 AI 命令正在执行'});
    if (command.trim().isEmpty) {
      return Future.value({'ok': false, 'error': '终端命令不能为空'});
    }
    final active = _Command(
      requestId,
      '__ENAI_${const Uuid().v4().replaceAll('-', '')}__',
      onProgress,
    );
    _active = active;
    active.timeout = Timer(
      timeout,
      () => _finish({'ok': false, 'error': '终端命令执行超时'}),
    );
    display('\r\n\x1b[36m\$ $command\x1b[0m\r\n');
    write(buildEnvelope(command, active.token));
    return active.completer.future;
  }

  static String buildEnvelope(String command, String token) {
    final encoded = base64.encode(utf8.encode(command));
    return "${token}_payload='$encoded'; printf '\\n$token:begin\\n'; "
        '(printf \'%s\' "\$${token}_payload" | base64 -d | env PAGER=cat SYSTEMD_PAGER= GIT_PAGER=cat LESS= sh); '
        '${token}_status=\$?; printf \'\\n$token:end:%s\\n\' "\$${token}_status"\n';
  }

  void output(String data) {
    final active = _active;
    if (active == null) {
      display(data);
      return;
    }
    active.pending += data;
    while (true) {
      final index = active.pending.indexOf('\n');
      if (index < 0) break;
      final line = active.pending.substring(0, index + 1);
      active.pending = active.pending.substring(index + 1);
      final plain = line
          .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
          .trim();
      if (plain == '${active.token}:begin') {
        active.started = true;
      } else if (RegExp('^${active.token}:end:[0-9]+\$').hasMatch(plain)) {
        final remainder = active.pending;
        _finish({'ok': true, 'exitCode': int.parse(plain.split(':').last)});
        if (remainder.isNotEmpty) display(remainder);
        return;
      } else if (!plain.contains(active.token)) {
        display(line);
        if (active.started) {
          active.output += line;
          if (active.output.length > 256 * 1024) {
            active.output = active.output.substring(
              active.output.length - 256 * 1024,
            );
          }
          active.progress ??= Timer(const Duration(milliseconds: 400), () {
            active.progress = null;
            active.onProgress?.call({
              'output': active.output.length > 12 * 1024
                  ? active.output.substring(active.output.length - 12 * 1024)
                  : active.output,
              'capturedAt': DateTime.now().millisecondsSinceEpoch,
              'durationMs': active.watch.elapsedMilliseconds,
            });
          });
        }
      }
    }
  }

  Future<Map<String, dynamic>> cancel(String requestId) async {
    final active = _active;
    if (active == null || active.id != requestId) {
      return {'ok': false, 'error': '终端命令已结束，无法确认中断状态'};
    }
    write('\x03');
    return active.completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => {'ok': false, 'error': '未收到终端结束确认，请在终端中核对远端命令'},
    );
  }

  void _finish(Map<String, dynamic> result) {
    final active = _active;
    if (active == null) return;
    _active = null;
    active.timeout?.cancel();
    active.progress?.cancel();
    active.completer.complete({
      ...result,
      'output': active.output,
      'capturedAt': DateTime.now().millisecondsSinceEpoch,
      'durationMs': active.watch.elapsedMilliseconds,
    });
  }

  void disconnect() => _finish({'ok': false, 'error': '终端连接已断开'});
}

class _Command {
  _Command(this.id, this.token, this.onProgress);
  final String id;
  final String token;
  final void Function(Map<String, dynamic>)? onProgress;
  final completer = Completer<Map<String, dynamic>>();
  final watch = Stopwatch()..start();
  String pending = '';
  String output = '';
  bool started = false;
  Timer? timeout;
  Timer? progress;
}
