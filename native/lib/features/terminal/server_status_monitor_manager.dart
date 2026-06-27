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

  Future<String> _run(SSHClient client, String command) async {
    final data = await client.run(command);
    return utf8.decode(data, allowMalformed: true);
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
    final client = runtime.client;
    if (client == null) return;
    const sep = '---EASYNODE_SEP---';
    final output = await _run(
      client,
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
    final client = runtime.client;
    if (client == null || runtime.refreshing) return;
    runtime.refreshing = true;
    try {
      // Group 0: Static info (first cycle only, one SSH channel)
      try {
        await _fetchStaticInfo(runtime);
      } catch (_) {}

      // Group 1: CPU (/proc/stat + uptime)
      try {
        final output = await _run(
          client,
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

      if (client.isClosed) return;

      // Group 2: Memory
      try {
        final output = await _run(client, 'free -m');
        final memory = ServerStatusParser.parseMemory(output);
        runtime.currentMemInfo = memory.memInfo;
        runtime.currentSwapInfo = memory.swapInfo;
        _emitSnapshot(runtime);
      } catch (_) {}

      if (client.isClosed) return;

      // Group 3: Disk
      try {
        final output = await _run(
          client,
          'df -kP -x tmpfs -x devtmpfs -x proc -x sysfs -x overlay',
        );
        runtime.currentDrivesInfo = ServerStatusParser.parseDrives(output);
        _emitSnapshot(runtime);
      } catch (_) {}

      if (client.isClosed) return;

      // Group 4: Network
      try {
        final now = DateTime.now();
        final output = await _run(client, 'cat /proc/net/dev');
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

class _MonitorRuntime {
  _MonitorRuntime({required this.entry});

  final ServerStatusMonitorEntry entry;
  SshTransportHandle? transport;
  SSHClient? client;
  Timer? timer;
  bool refreshing = false;

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

  Future<void> close({bool keepEntryState = false}) async {
    timer?.cancel();
    timer = null;
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
