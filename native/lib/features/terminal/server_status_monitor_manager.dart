import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'server_status_snapshot.dart';
import 'ssh_connection_config.dart';
import 'ssh_transport.dart';

enum ServerStatusMonitorState { idle, connecting, connected, error }

class ServerStatusMonitorEntry {
  ServerStatusMonitorEntry({required this.hostId, required this.config});

  final String hostId;
  SshConnectionConfig config;
  final Set<String> refSessionIds = <String>{};
  ServerStatusMonitorState state = ServerStatusMonitorState.idle;
  ServerStatusSnapshot? snapshot;
  String? lastError;
  DateTime? lastUpdatedAt;
}

class ServerStatusMonitorManager extends ChangeNotifier {
  ServerStatusMonitorManager({
    SshTransportFactory? transportFactory,
    Duration refreshInterval = const Duration(seconds: 2),
  }) : _transportFactory = transportFactory ?? SshTransportFactory(),
       _refreshInterval = refreshInterval;

  final SshTransportFactory _transportFactory;
  final Duration _refreshInterval;
  final Map<String, _MonitorRuntime> _runtimes = {};

  Iterable<ServerStatusMonitorEntry> get entries =>
      _runtimes.values.map((runtime) => runtime.entry).toList(growable: false);

  ServerStatusMonitorEntry? entryForHost(String hostId) =>
      _runtimes[hostId]?.entry;

  Future<void> attach({
    required String sessionId,
    required SshConnectionConfig config,
  }) async {
    if (config.hostId.isEmpty) return;
    final runtime = _runtimes.putIfAbsent(
      config.hostId,
      () => _MonitorRuntime(
        entry: ServerStatusMonitorEntry(hostId: config.hostId, config: config),
      ),
    );
    runtime.entry.config = config;
    runtime.entry.refSessionIds.add(sessionId);
    notifyListeners();
    if (runtime.entry.state == ServerStatusMonitorState.connected ||
        runtime.entry.state == ServerStatusMonitorState.connecting) {
      return;
    }
    await _connect(runtime);
  }

  Future<void> startNow(SshConnectionConfig config) async {
    if (config.hostId.isEmpty) return;
    final runtime = _runtimes.putIfAbsent(
      config.hostId,
      () => _MonitorRuntime(
        entry: ServerStatusMonitorEntry(hostId: config.hostId, config: config),
      ),
    );
    runtime.entry.config = config;
    if (runtime.entry.state == ServerStatusMonitorState.connecting) return;
    if (runtime.entry.state == ServerStatusMonitorState.connected) {
      await refresh(config.hostId);
      return;
    }
    await _connect(runtime);
  }

  Future<void> detach({
    required String sessionId,
    required String hostId,
  }) async {
    final runtime = _runtimes[hostId];
    if (runtime == null) return;
    runtime.entry.refSessionIds.remove(sessionId);
    if (runtime.entry.refSessionIds.isNotEmpty) {
      notifyListeners();
      return;
    }
    _runtimes.remove(hostId);
    await runtime.close();
    notifyListeners();
  }

  // 刷新按钮：彻底丢弃旧的 SSH 连接（含持久化 shell），重新建立一条全新连接
  Future<void> refresh(String hostId) async {
    final runtime = _runtimes[hostId];
    if (runtime == null) return;
    await runtime.close();
    await _connect(runtime);
  }

  Future<void> disconnectHost(String hostId) async {
    final runtime = _runtimes.remove(hostId);
    if (runtime == null) return;
    await runtime.close();
    notifyListeners();
  }

  Future<void> _connect(_MonitorRuntime runtime) async {
    runtime.entry.state = ServerStatusMonitorState.connecting;
    runtime.entry.lastError = null;
    notifyListeners();
    try {
      runtime.transport = await _transportFactory.open(runtime.entry.config);
      final identities = runtime.entry.config.authType == 'privateKey'
          ? SSHKeyPair.fromPem(
              runtime.entry.config.privateKey,
              runtime.entry.config.privateKeyPassphrase,
            )
          : null;
      runtime.client = SSHClient(
        runtime.transport!.socket,
        username: runtime.entry.config.username,
        onPasswordRequest: runtime.entry.config.authType == 'password'
            ? () => runtime.entry.config.password
            : null,
        identities: identities,
      );
      // 整个连接生命周期只开一条持久化 shell，后续所有采集命令复用同一个远端 bash 进程
      await _initPersistentShell(runtime);
      runtime.entry.state = ServerStatusMonitorState.connected;
      notifyListeners();
      await _refresh(runtime);
      runtime.timer = Timer.periodic(_refreshInterval, (_) {
        unawaited(_refresh(runtime));
      });
    } catch (error) {
      await runtime.close();
      runtime.entry.state = ServerStatusMonitorState.error;
      runtime.entry.lastError = error.toString();
      notifyListeners();
    }
  }

  // 打开一条持久化 shell（不分配 pty，输出干净不含控制字符），
  // 之后所有采集命令都写入这同一个 bash 的 stdin，靠 marker 识别输出边界，
  // 全程只 fork 一次远端 shell，而不是每组数据都开一个新 exec channel
  Future<void> _initPersistentShell(_MonitorRuntime runtime) async {
    final client = runtime.client;
    if (client == null) throw StateError('SSH client not ready');

    final session = await client.execute('/bin/bash --noprofile --norc -i');
    runtime.persistentShell = session;
    runtime.shellReady = true;
    runtime.shellBuffer = '';

    session.write(Uint8List.fromList(utf8.encode('unset HISTFILE\n')));

    runtime.shellStdoutSub = session.stdout.listen(
      (data) {
        runtime.shellBuffer += utf8.decode(data, allowMalformed: true);
        _drainShellBuffer(runtime);
      },
      onDone: () {
        runtime.shellReady = false;
        runtime.persistentShell = null;
        runtime.rejectPendingShellCommands(
          StateError('persistent shell closed'),
        );
      },
      onError: (_) {
        runtime.shellReady = false;
        runtime.persistentShell = null;
        runtime.rejectPendingShellCommands(
          StateError('persistent shell error'),
        );
      },
    );
  }

  // 按行切分 shell 输出，遇到队首命令的 marker 即视为该命令输出完毕
  void _drainShellBuffer(_MonitorRuntime runtime) {
    int index;
    while ((index = runtime.shellBuffer.indexOf('\n')) != -1) {
      final line = runtime.shellBuffer.substring(0, index).trimRight();
      runtime.shellBuffer = runtime.shellBuffer.substring(index + 1);
      if (runtime.shellCmdQueue.isEmpty) continue;
      final current = runtime.shellCmdQueue.first;
      if (line == current.marker) {
        runtime.shellCmdQueue.removeAt(0);
        if (!current.completer.isCompleted) {
          current.completer.complete(current.output.toString().trimRight());
        }
        if (runtime.shellCmdQueue.isNotEmpty) {
          _sendNextShellCommand(runtime);
        }
      } else {
        current.output.writeln(line);
      }
    }
  }

  void _sendNextShellCommand(_MonitorRuntime runtime) {
    if (runtime.shellCmdQueue.isEmpty ||
        !runtime.shellReady ||
        runtime.persistentShell == null) {
      return;
    }
    final current = runtime.shellCmdQueue.first;
    runtime.persistentShell!.write(
      Uint8List.fromList(
        utf8.encode(' ${current.command}; echo ${current.marker}\n'),
      ),
    );
  }

  // 通过持久化 shell 执行命令（取代原先每次都新开 exec channel 的 client.run）
  Future<String> _executeShellCommand(_MonitorRuntime runtime, String command) {
    if (!runtime.shellReady || runtime.persistentShell == null) {
      return Future.error(StateError('persistent shell not ready'));
    }
    final marker = '__EZCMD_END_${++runtime.shellCmdCounter}__';
    final task = _PendingShellCommand(command, marker);
    runtime.shellCmdQueue.add(task);
    if (runtime.shellCmdQueue.length == 1) {
      _sendNextShellCommand(runtime);
    }
    return task.completer.future;
  }

  void _emitSnapshot(_MonitorRuntime runtime) {
    final now = DateTime.now();
    runtime.entry.snapshot = ServerStatusSnapshot(
      connect: true,
      cpuInfo: CpuInfo(
        cpuUsage: runtime.currentCpuUsage,
        cpuCount: runtime.cachedCpuCount,
        cpuModel: runtime.cachedCpuModel,
        loadAvg: runtime.currentLoadAvg,
      ),
      memInfo: runtime.currentMemInfo,
      swapInfo: runtime.currentSwapInfo,
      drivesInfo: runtime.currentDrivesInfo,
      netstatInfo: runtime.currentNetstatInfo,
      osInfo: OsInfo(
        hostname: runtime.cachedHostname,
        type: runtime.cachedOsType,
        release: runtime.cachedOsRelease,
        arch: runtime.cachedArch,
        uptime: runtime.currentUptime,
      ),
      updatedAt: now,
    );
    runtime.entry.lastUpdatedAt = now;
    runtime.entry.lastError = null;
    runtime.entry.state = ServerStatusMonitorState.connected;
    notifyListeners();
  }

  Future<void> _fetchStaticInfo(_MonitorRuntime runtime) async {
    if (runtime.staticInfoFetched) return;
    const sep = '---EASYNODE_SEP---';
    final output = await _executeShellCommand(
      runtime,
      'hostname\necho $sep'
      '\ncat /etc/os-release\necho $sep'
      '\nuname -m\necho $sep'
      '\nnproc\necho $sep'
      '\ngrep "model name" /proc/cpuinfo | head -1\necho $sep'
      "\nip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if(\$i==\"dev\") {print \$(i+1); exit}}'",
    );
    final parts = output.split(sep);
    String part(int i) => i < parts.length ? parts[i].trim() : '';
    runtime.cachedHostname = part(0).isEmpty ? 'Unknown' : part(0);
    final osInfo = ServerStatusParser.parseOsInfo(
      hostname: part(0),
      osRelease: part(1),
      arch: part(2),
      uptimeOutput: '',
    );
    runtime.cachedOsType = osInfo.type;
    runtime.cachedOsRelease = osInfo.release;
    runtime.cachedArch = osInfo.arch;
    runtime.cachedCpuCount = ServerStatusParser.parseCpuCount(part(3));
    runtime.cachedCpuModel = ServerStatusParser.parseCpuModel(part(4));
    runtime.cachedDefaultInterface =
        ServerStatusParser.parseDefaultInterface(part(5));
    runtime.staticInfoFetched = true;
  }

  Future<void> _refresh(_MonitorRuntime runtime) async {
    if (!runtime.shellReady || runtime.refreshing) return;
    runtime.refreshing = true;
    try {
      // Group 0: Static info (first cycle only, one command through the persistent shell)
      try {
        await _fetchStaticInfo(runtime);
      } catch (_) {}

      // Group 1: CPU (/proc/stat + uptime)
      try {
        final output = await _executeShellCommand(
          runtime,
          'cat /proc/stat\necho ---EASYNODE_SEP---\ncat /proc/uptime && uptime',
        );
        final parts = output.split('---EASYNODE_SEP---');
        final procStats = ServerStatusParser.parseProcStat(
          parts.isNotEmpty ? parts[0].trim() : '',
        );
        runtime.currentCpuUsage = ServerStatusParser.cpuUsage(
          previous: runtime.previousCpuStats,
          current: procStats,
        );
        runtime.previousCpuStats = procStats;
        final uptimeOutput = parts.length > 1 ? parts[1].trim() : '';
        runtime.currentLoadAvg = ServerStatusParser.parseLoadAverage(
          uptimeOutput,
        );
        final uptimeVal = double.tryParse(
          uptimeOutput.trim().split(RegExp(r'\s+')).first,
        );
        if (uptimeVal != null) runtime.currentUptime = uptimeVal;
        _emitSnapshot(runtime);
      } catch (_) {}

      if (!runtime.shellReady) return;

      // Group 2: Memory (+ cgroup 内存/交换分区限制，容器化环境下 free -k 反映的是宿主机数据)
      try {
        const memSep = '---EASYNODE_MEMSEP---';
        final output = await _executeShellCommand(
          runtime,
          'free -k\necho $memSep'
          '\nif [ -f /sys/fs/cgroup/memory.max ]; then echo v2; '
          'cat /sys/fs/cgroup/memory.max; cat /sys/fs/cgroup/memory.current; '
          'cat /sys/fs/cgroup/memory.swap.max 2>/dev/null || echo na; '
          'cat /sys/fs/cgroup/memory.swap.current 2>/dev/null || echo na; '
          'elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then echo v1; '
          'cat /sys/fs/cgroup/memory/memory.limit_in_bytes; '
          'cat /sys/fs/cgroup/memory/memory.usage_in_bytes; echo na; echo na; '
          'else echo none; fi',
        );
        final parts = output.split(memSep);
        final hostMemory = ServerStatusParser.parseMemory(
          parts.isNotEmpty ? parts[0] : '',
        );
        final cgroupMemory = parts.length > 1
            ? ServerStatusParser.parseCgroupMemory(parts[1])
            : null;
        final memory = ServerStatusParser.applyCgroupOverride(
          hostMemory,
          cgroupMemory,
        );
        runtime.currentMemInfo = memory.memInfo;
        runtime.currentSwapInfo = memory.swapInfo;
        _emitSnapshot(runtime);
      } catch (_) {}

      if (!runtime.shellReady) return;

      // Group 3: Disk
      try {
        final output = await _executeShellCommand(
          runtime,
          'df -kP -x tmpfs -x devtmpfs -x proc -x sysfs -x overlay',
        );
        runtime.currentDrivesInfo = ServerStatusParser.parseDrives(output);
        _emitSnapshot(runtime);
      } catch (_) {}

      if (!runtime.shellReady) return;

      // Group 4: Network
      try {
        final now = DateTime.now();
        final output = await _executeShellCommand(runtime, 'cat /proc/net/dev');
        final counters = ServerStatusParser.parseNetworkCounters(output);
        runtime.currentNetstatInfo = ServerStatusParser.networkRate(
          previous: runtime.previousNetworkCounters,
          current: counters,
          previousAt: runtime.previousNetworkAt,
          currentAt: now,
          defaultInterface: runtime.cachedDefaultInterface,
        );
        runtime.previousNetworkCounters = counters;
        runtime.previousNetworkAt = now;
        _emitSnapshot(runtime);
      } catch (_) {}
    } catch (error) {
      runtime.entry.lastError = error.toString();
      runtime.entry.state = ServerStatusMonitorState.error;
      notifyListeners();
      await runtime.close(keepEntryState: true);
    } finally {
      runtime.refreshing = false;
    }
  }

  @override
  void dispose() {
    final runtimes = _runtimes.values.toList(growable: false);
    _runtimes.clear();
    for (final runtime in runtimes) {
      unawaited(runtime.close());
    }
    super.dispose();
  }
}

// 排队中的单条 shell 命令：等待输出中出现 marker 才算完成
class _PendingShellCommand {
  _PendingShellCommand(this.command, this.marker);

  final String command;
  final String marker;
  final Completer<String> completer = Completer<String>();
  final StringBuffer output = StringBuffer();
}

class _MonitorRuntime {
  _MonitorRuntime({required this.entry});

  final ServerStatusMonitorEntry entry;
  SshTransportHandle? transport;
  SSHClient? client;
  Timer? timer;
  bool refreshing = false;

  // 持久化 shell（整个连接生命周期只开一条，采集命令全部复用它）
  SSHSession? persistentShell;
  bool shellReady = false;
  StreamSubscription<Uint8List>? shellStdoutSub;
  final List<_PendingShellCommand> shellCmdQueue = [];
  int shellCmdCounter = 0;
  String shellBuffer = '';

  // Delta tracking
  ProcCpuStats? previousCpuStats;
  NetworkCounters? previousNetworkCounters;
  DateTime? previousNetworkAt;

  // Static info cache (fetched once per connection)
  bool staticInfoFetched = false;
  String cachedHostname = 'Unknown';
  String cachedOsType = 'Linux';
  String cachedOsRelease = 'Unknown';
  String cachedArch = 'Unknown';
  int cachedCpuCount = 0;
  String cachedCpuModel = 'Unknown';
  String? cachedDefaultInterface;

  // Current dynamic values (updated progressively per group)
  double currentCpuUsage = 0;
  List<double> currentLoadAvg = const [0, 0, 0];
  double currentUptime = 0;
  MemoryInfo currentMemInfo = const MemoryInfo(
    totalMemMb: 0, usedMemMb: 0, freeMemMb: 0,
    usedMemPercentage: 0, freeMemPercentage: 0,
  );
  SwapInfo currentSwapInfo = const SwapInfo(
    swapTotal: 0, swapUsed: 0, swapFree: 0, swapPercentage: 0,
  );
  List<DriveInfo> currentDrivesInfo = const [];
  NetstatInfo currentNetstatInfo = const NetstatInfo(
    inputMb: 0, outputMb: 0, interfaceName: null,
  );

  // 让所有还在排队/等待中的命令立即失败，而不是永久挂起
  // （挂起会导致 _refresh 里的 finally 永远跑不到，refreshing 卡死为 true，
  // 后续所有刷新——包括手动点刷新重连后的第一次——都会被挡在最前面的判断里）
  void rejectPendingShellCommands(Object error) {
    final pending = List<_PendingShellCommand>.from(shellCmdQueue);
    shellCmdQueue.clear();
    for (final task in pending) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(error);
      }
    }
  }

  Future<void> close({bool keepEntryState = false}) async {
    timer?.cancel();
    timer = null;

    shellReady = false;
    rejectPendingShellCommands(StateError('monitor connection closed'));

    await shellStdoutSub?.cancel();
    shellStdoutSub = null;
    persistentShell?.close();
    persistentShell = null;
    shellBuffer = '';

    final oldClient = client;
    final oldTransport = transport;
    client = null;
    transport = null;
    oldClient?.close();
    await oldTransport?.close();
    previousCpuStats = null;
    previousNetworkCounters = null;
    previousNetworkAt = null;
    if (!keepEntryState) {
      staticInfoFetched = false;
      entry.state = ServerStatusMonitorState.idle;
    }
  }
}
