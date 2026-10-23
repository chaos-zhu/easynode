import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easynode_native/features/rdp/desktop_rdp_workspace.dart';
import 'package:easynode_native/features/rdp/rdp_engine.dart';
import 'package:easynode_native/features/servers/server_model.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _Input implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      bytes.addAll(data);
    }
  }

  @override
  Future<void> close() async {}
}

class _Process implements Process {
  final input = _Input();
  late final IOSink _stdin = IOSink(input);
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exit = Completer<int>();
  bool killed = false;
  @override
  IOSink get stdin => _stdin;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  int get pid => 42;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!exit.isCompleted) exit.complete(0);
    return true;
  }

  void connected() => output.add(utf8.encode('EASYNODE_RDP connected\n'));
  Future<void> cleanup() async {
    kill();
    await stdin.close();
    await output.close();
    await errors.close();
  }
}

SshConnectionConfig config(String id) => SshConnectionConfig.fromJson({
  'hostId': id,
  'name': 'Windows $id',
  'host': '2001:db8::1',
  'port': 3389,
  'username': 'DOMAIN\\user',
  'authType': 'password',
  'password': '秘密!\n123',
});
ServerModel server(String id) => ServerModel.fromJson({
  'id': id,
  'name': id,
  'host': '10.0.0.2',
  'port': 3389,
  'connectType': 'rdp',
  'authType': 'password',
  'isConfig': true,
});
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'password uses a binary memory pipe; arguments preserve IPv6 and certificate verification',
    () async {
      final process = _Process();
      addTearDown(process.cleanup);
      late List<String> args;
      final engine = RdpEngine(
        executable: () async => '/bundled/easynode-rdp',
        startProcess: (exe, values) async {
          expect(exe, '/bundled/easynode-rdp');
          args = values;
          return process;
        },
      );
      final window = await engine.open(config('one'), const RdpOptions());
      expect(args, contains('/v:[2001:db8::1]:3389'));
      expect(args, contains('+dynamic-resolution'));
      expect(args.join(' '), isNot(contains(config('one').password)));
      expect(args.join(' '), isNot(contains('/p:')));
      expect(args.join(' '), isNot(contains('cert:ignore')));
      final data = Uint8List.fromList(process.input.bytes);
      final size = ByteData.sublistView(data).getUint32(0);
      expect(utf8.decode(data.sublist(4, 4 + size)), config('one').password);
      process.connected();
      expect(await window.connected, isTrue);
      await window.focus();
      expect(utf8.decode(process.input.bytes.sublist(4 + size)), 'focus\n');
      process.exit.complete(0);
      expect(await window.done, 0);
    },
  );

  test(
    'tunneled arguments verify and authenticate against the original host',
    () {
      final args = const RdpOptions(
        resolution: '1920x1080',
        quality: RdpQuality.low,
        clipboard: false,
      ).arguments(config('one'), tunnelPort: 45321);
      expect(
        args,
        containsAll([
          '/v:127.0.0.1:45321',
          '/server-name:2001:db8::1',
          '/cert:name:2001:db8::1',
          '/size:1920x1080',
          '-clipboard',
          '/network:modem',
        ]),
      );
      expect(args, isNot(contains('+dynamic-resolution')));
    },
  );

  test(
    'each host has its own window; selecting an existing host focuses it; logout terminates both',
    () async {
      final processes = <_Process>[];
      final workspace = DesktopRdpWorkspace(
        fetch: (id) async => config(id),
        engine: RdpEngine(
          executable: () async => '/bundled/engine',
          startProcess: (_, _) async {
            final process = _Process();
            processes.add(process);
            return process;
          },
        ),
      );
      addTearDown(() async {
        for (final p in processes) {
          await p.cleanup();
        }
      });
      final first = workspace.open(server('one'));
      await settle();
      expect(workspace.connections.single.status, RdpWindowStatus.connecting);
      processes.single.connected();
      await first;
      final second = workspace.open(server('two'));
      await settle();
      processes.last.connected();
      await second;
      await workspace.open(server('one'));
      expect(processes.length, 2);
      expect(
        utf8.decode(processes.first.input.bytes, allowMalformed: true),
        endsWith('focus\n'),
      );
      expect(
        workspace.connections.every(
          (c) => c.status == RdpWindowStatus.connected,
        ),
        isTrue,
      );
      workspace.dispose();
      expect(processes.every((p) => p.killed), isTrue);
      await settle();
    },
  );

  test(
    'engine rejection becomes a recoverable card and retry refetches credentials',
    () async {
      var requests = 0;
      final workspace = DesktopRdpWorkspace(
        fetch: (_) async {
          requests++;
          throw StateError('Plus required');
        },
      );
      addTearDown(workspace.dispose);
      await workspace.open(server('one'));
      expect(workspace.connections.single.status, RdpWindowStatus.error);
      expect(workspace.connections.single.error, contains('Plus required'));
      await workspace.open(server('one'));
      expect(requests, 2);
      expect(workspace.connections.length, 1);
      await workspace.close(workspace.connections.single);
      expect(workspace.connections, isEmpty);
    },
  );

  test('failed engine exit never reports a connected window', () async {
    final process = _Process();
    addTearDown(process.cleanup);
    final workspace = DesktopRdpWorkspace(
      fetch: (id) async => config(id),
      engine: RdpEngine(
        executable: () async => 'engine',
        startProcess: (_, _) async => process,
      ),
    );
    addTearDown(workspace.dispose);
    final opening = workspace.open(server('one'));
    await settle();
    process.exit.complete(131);
    await opening;
    await settle();
    expect(workspace.connections.single.status, RdpWindowStatus.error);
    expect(workspace.connections.single.error, contains('131'));
  });
}
