import 'package:easynode_native/features/terminal/server_status_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses proc stat and calculates cpu usage', () {
    final previous = ServerStatusParser.parseProcStat(
      'cpu  100 0 100 800 0 0 0 0 0 0\n',
    );
    final current = ServerStatusParser.parseProcStat(
      'cpu  150 0 150 900 0 0 0 0 0 0\n',
    );

    expect(previous, isNotNull);
    expect(current, isNotNull);
    expect(
      ServerStatusParser.cpuUsage(previous: previous, current: current),
      50,
    );
  });

  test('parses memory and swap from free output', () {
    final parsed = ServerStatusParser.parseMemory('''
              total        used        free      shared  buff/cache   available
Mem:           7987        1996        1000          11        4991        5600
Swap:          2047         512        1535
''');

    expect(parsed.memInfo.totalMemMb, 7987);
    expect(parsed.memInfo.usedMemMb, 1996);
    expect(parsed.memInfo.usedMemPercentage, closeTo(24.99, 0.01));
    expect(parsed.swapInfo.swapPercentage, closeTo(25.01, 0.01));
  });

  test('filters and parses physical drives', () {
    final drives = ServerStatusParser.parseDrives('''
Filesystem     1024-blocks    Used Available Capacity Mounted on
tmpfs              1000000       1    999999       1% /run
/dev/vda1        52428800 10485760  41943040      20% /
/dev/loop0        1048576  1048576         0     100% /snap
''');

    expect(drives, hasLength(1));
    expect(drives.first.filesystem, '/dev/vda1');
    expect(drives.first.totalGb, 50);
    expect(drives.first.usedPercentage, 20);
  });

  test('parses network counters and calculates rate', () {
    final previous = ServerStatusParser.parseNetworkCounters('''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0
    lo: 100 0 0 0 0 0 0 0 100 0 0 0 0 0 0 0
''');
    final current = ServerStatusParser.parseNetworkCounters('''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 3145728 0 0 0 0 0 0 0 3145728 0 0 0 0 0 0 0
''');

    final rate = ServerStatusParser.networkRate(
      previous: previous,
      current: current,
      previousAt: DateTime(2026),
      currentAt: DateTime(2026).add(const Duration(seconds: 2)),
      defaultInterface: 'eth0',
    );

    expect(rate.inputMb, 1);
    expect(rate.outputMb, 0.5);
    expect(rate.interfaceName, 'eth0');
  });
}
