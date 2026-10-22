import 'dart:convert';

import 'package:easynode_native/features/terminal/desktop/terminal_command_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> writes, visible;
  late TerminalCommandBridge bridge;
  setUp(() {
    writes = [];
    visible = [];
    bridge = TerminalCommandBridge(write: writes.add, display: visible.add);
  });
  tearDown(() => bridge.disconnect());
  String token() =>
      RegExp(r'__ENAI_[a-f0-9]+__').firstMatch(writes.first)!.group(0)!;
  test(
    'envelope encodes unicode and shell metacharacters without interpolation',
    () {
      const command = 'printf "你好"; echo \$(date); exit 7';
      final envelope = TerminalCommandBridge.buildEnvelope(
        command,
        '__TOKEN__',
      );
      expect(envelope, contains(base64Encode(utf8.encode(command))));
      expect(envelope, contains('"\$__TOKEN___payload"'));
      expect(envelope, contains('env PAGER=cat'));
      expect(envelope, contains('__TOKEN__:end:%s'));
      expect(envelope, endsWith('\n'));
      expect(envelope, isNot(contains(command)));
    },
  );
  test(
    'echo cannot finish command; markers spanning chunks are hidden',
    () async {
      final result = bridge.execute('echo hello', 'one');
      final marker = token();
      bridge.output('${writes.first}\r\n');
      expect(bridge.busy, true);
      bridge.output('$marker:be');
      bridge.output('gin\r\nhello\r\n$marker:en');
      bridge.output('d:7\r\nuser@host:~\$ ');
      final response = await result;
      expect(response['ok'], true);
      expect(response['exitCode'], 7);
      expect(response['output'], 'hello\r\n');
      expect(visible.join(), contains('user@host:~\$ '));
      expect(visible.join(), isNot(contains(marker)));
      expect(bridge.busy, false);
    },
  );
  test('cancel sends Ctrl C and waits for actual completion', () async {
    final result = bridge.execute('sleep 100', 'request');
    final marker = token();
    bridge.output('$marker:begin\n');
    var done = false;
    final cancellation = bridge.cancel('request').then((value) {
      done = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(writes.last, '\x03');
    expect(done, false);
    bridge.output('$marker:end:130\n');
    expect((await cancellation)['exitCode'], 130);
    expect((await result)['exitCode'], 130);
  });
  test('disconnect settles pending operation and releases bridge', () async {
    final result = bridge.execute('sleep 10', 'one');
    final rejected = await bridge.execute('second', 'two');
    expect(rejected['ok'], false);
    bridge.disconnect();
    expect((await result)['ok'], false);
    expect(bridge.busy, false);
    bridge.output('normal prompt');
    expect(visible.last, 'normal prompt');
  });
}
