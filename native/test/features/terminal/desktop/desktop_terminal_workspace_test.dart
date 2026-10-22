import 'package:easynode_native/features/terminal/desktop/desktop_terminal_settings.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_workspace.dart';
import 'package:easynode_native/features/terminal/ssh_connection_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'desktop_test_support.dart';

void main() {
  late DesktopTerminalWorkspace workspace;
  late List<FakeConnection> connections;
  late FakeMonitor monitor;
  late int configReads;
  setUp(() {
    connections = [];
    configReads = 0;
    monitor = FakeMonitor();
    final settings = DesktopTerminalSettings.defaults();
    settings.behavior['autoReconnect'] = false;
    workspace = DesktopTerminalWorkspace(
      loadConfig: (id) async {
        configReads++;
        return SshConnectionConfig.fromJson({
          'hostId': id,
          'host': '127.0.0.1',
          'password': 'revision-$configReads',
        });
      },
      settings: () => settings,
      monitor: monitor,
      connectionFactory: () {
        final connection = FakeConnection();
        connections.add(connection);
        return connection;
      },
    );
  });
  tearDown(() => workspace.dispose());
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  test(
    'mounting state makes no connection; tabs retain output and connection on activation',
    () async {
      expect(connections, isEmpty);
      final one = workspace.open(host('one'));
      await settle();
      connections[0].output('persistent output');
      final two = workspace.open(host('two'));
      await settle();
      workspace.activate(one);
      workspace.activate(two);
      workspace.activate(one);
      expect(connections, hasLength(2));
      expect(connections.every((c) => c.connects == 1), true);
      expect(one.activePane.output, contains('persistent output'));
      expect(monitor.attached, hasLength(2));
      workspace.closeOthers(one);
      await settle();
      expect(workspace.tabs, [one]);
      expect(connections[1].closes, 1);
      expect(connections[0].closes, 0);
      expect(monitor.attached, hasLength(1));
    },
  );
  test(
    'splits own independent PTYs; sync input is scoped and never loops',
    () async {
      final one = workspace.open(host('one'));
      final two = workspace.open(host('two'));
      await settle();
      workspace.toggleSplit(one, horizontal: true);
      await settle();
      expect(one.panes, hasLength(2));
      expect(connections, hasLength(3));
      workspace.input(one.panes.first, 'a');
      expect(connections.map((c) => c.writes.join()).toList(), ['a', '', '']);
      one.syncInput = true;
      workspace.input(one.panes.first, 'b');
      expect(connections.map((c) => c.writes.join()).toList(), ['ab', '', 'b']);
      workspace.syncAll = true;
      workspace.input(two.activePane, 'c');
      expect(connections.map((c) => c.writes.join()).toList(), [
        'abc',
        'c',
        'bc',
      ]);
      workspace.input(one.activePane, 'private', synchronize: false);
      expect(connections[0].writes.last, 'private');
      expect(connections[1].writes.last, 'c');
      workspace.toggleSplit(one, horizontal: false);
      await settle();
      expect(one.panes, hasLength(4));
      workspace.toggleSplit(one, horizontal: true);
      await settle();
      expect(one.panes, hasLength(2));
      expect(connections.where((c) => c.closes > 0), hasLength(2));
      workspace.closeAll();
      await settle();
      expect(workspace.tabs, isEmpty);
      expect(connections.every((c) => c.closes == 1), true);
    },
  );
  test(
    'AI execution targets one pane even with global synchronization enabled',
    () async {
      final one = workspace.open(host('one'));
      workspace.open(host('two'));
      await settle();
      workspace.syncAll = true;
      final future = workspace.executeAi(one.activePane, 'echo hi', 'request');
      expect(connections[0].writes, hasLength(1));
      expect(connections[1].writes, isEmpty);
      final token = RegExp(
        r'__ENAI_[a-f0-9]+__',
      ).firstMatch(connections[0].writes.single)!.group(0)!;
      connections[0].output('$token:begin\nhi\n$token:end:0\n');
      expect((await future)['output'], 'hi\n');
    },
  );
  test('reconnect fetches new credentials and closes old connection', () async {
    final one = workspace.open(host('one'));
    await settle();
    connections[0].output('before');
    connections[0].closed(StateError('network lost'));
    expect(one.activePane.status, DesktopTerminalStatus.disconnected);
    await workspace.reconnect(one.activePane);
    expect(configReads, 2);
    expect(connections, hasLength(2));
    expect(connections.first.closes, 1);
    expect(connections.last.config!.password, 'revision-2');
    expect(one.activePane.status, DesktopTerminalStatus.connected);
    expect(one.activePane.output, contains('before'));
  });
  test(
    'closing one split pane retains the other PTYs and supports further splitting',
    () async {
      final tab = workspace.open(host('one'));
      workspace.toggleSplit(tab, horizontal: true);
      workspace.toggleSplit(tab, horizontal: false);
      await settle();
      final remaining = tab.panes.first;
      final removed = tab.panes[1];
      workspace.closePane(tab, removed);
      await settle();
      expect(tab.panes, hasLength(3));
      expect(removed.closed, isTrue);
      expect(remaining.closed, isFalse);
      expect(connections.where((c) => c.closes > 0), hasLength(1));
      workspace.toggleSplit(tab, horizontal: false);
      await settle();
      expect(tab.panes, hasLength(2));
      expect(tab.panes.first, same(remaining));
      workspace.closePane(tab, tab.panes.last);
      expect(tab.horizontal, isFalse);
      expect(tab.vertical, isFalse);
      workspace.closePane(tab, remaining);
      expect(workspace.tabs, isEmpty);
    },
  );
}
