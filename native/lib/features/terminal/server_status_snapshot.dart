import 'dart:math' show max, min;

class ServerStatusSnapshot {
  const ServerStatusSnapshot({
    required this.connect,
    required this.cpuInfo,
    required this.memInfo,
    required this.swapInfo,
    required this.drivesInfo,
    required this.netstatInfo,
    required this.osInfo,
    required this.updatedAt,
  });

  final bool connect;
  final CpuInfo cpuInfo;
  final MemoryInfo memInfo;
  final SwapInfo swapInfo;
  final List<DriveInfo> drivesInfo;
  final NetstatInfo netstatInfo;
  final OsInfo osInfo;
  final DateTime updatedAt;
}

class CpuInfo {
  const CpuInfo({
    required this.cpuUsage,
    required this.cpuCount,
    required this.cpuModel,
    required this.loadAvg,
  });

  final double cpuUsage;
  final int cpuCount;
  final String cpuModel;
  final List<double> loadAvg;
}

class MemoryInfo {
  const MemoryInfo({
    required this.totalMemMb,
    required this.usedMemMb,
    required this.freeMemMb,
    required this.usedMemPercentage,
    required this.freeMemPercentage,
  });

  final int totalMemMb;
  final int usedMemMb;
  final int freeMemMb;
  final double usedMemPercentage;
  final double freeMemPercentage;
}

class SwapInfo {
  const SwapInfo({
    required this.swapTotal,
    required this.swapUsed,
    required this.swapFree,
    required this.swapPercentage,
  });

  final int swapTotal;
  final int swapUsed;
  final int swapFree;
  final double swapPercentage;
}

class DriveInfo {
  const DriveInfo({
    required this.filesystem,
    required this.mountedOn,
    required this.totalGb,
    required this.usedGb,
    required this.freeGb,
    required this.usedPercentage,
    required this.freePercentage,
  });

  final String filesystem;
  final String mountedOn;
  final double totalGb;
  final double usedGb;
  final double freeGb;
  final double usedPercentage;
  final double freePercentage;
}

class NetstatInfo {
  const NetstatInfo({
    required this.inputMb,
    required this.outputMb,
    required this.interfaceName,
  });

  final double inputMb;
  final double outputMb;
  final String? interfaceName;
}

class OsInfo {
  const OsInfo({
    required this.hostname,
    required this.type,
    required this.release,
    required this.arch,
    required this.uptime,
  });

  final String hostname;
  final String type;
  final String release;
  final String arch;
  final double uptime;
}

class ProcCpuStats {
  const ProcCpuStats({required this.idle, required this.total});

  final int idle;
  final int total;
}

class NetworkCounters {
  const NetworkCounters({
    required this.rxBytes,
    required this.txBytes,
    required this.interfaces,
  });

  final int rxBytes;
  final int txBytes;
  final Map<String, NetworkInterfaceCounters> interfaces;
}

class NetworkInterfaceCounters {
  const NetworkInterfaceCounters({
    required this.rxBytes,
    required this.txBytes,
  });

  final int rxBytes;
  final int txBytes;
}
class ServerStatusParser {
  static ProcCpuStats? parseProcStat(String output) {
    final firstLine = output
        .split('\n')
        .where((line) => line.startsWith('cpu '))
        .firstOrNull;
    if (firstLine == null) return null;
    final values = firstLine
        .trim()
        .split(RegExp(r'\s+'))
        .skip(1)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    if (values.length < 4) return null;
    return ProcCpuStats(
      idle: values[3],
      total: values.fold<int>(0, (sum, value) => sum + value),
    );
  }

  static double cpuUsage({
    required ProcCpuStats? previous,
    required ProcCpuStats? current,
  }) {
    if (previous == null || current == null) return 0;
    final totalDiff = current.total - previous.total;
    final idleDiff = current.idle - previous.idle;
    if (totalDiff <= 0) return 0;
    return _round2(max(0, min(100, (1 - idleDiff / totalDiff) * 100)));
  }

  static List<double> parseLoadAverage(String uptimeOutput) {
    final match = RegExp(
      r'load average(?:s)?:\s*([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)',
    ).firstMatch(uptimeOutput);
    if (match == null) return const [0, 0, 0];
    return [
      double.tryParse(match.group(1) ?? '') ?? 0,
      double.tryParse(match.group(2) ?? '') ?? 0,
      double.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  static MemorySwapInfo parseMemory(String output) {
    final lines = output.split('\n');
    final memLine = lines
        .where((line) => line.trimLeft().startsWith('Mem:'))
        .firstOrNull;
    final swapLine = lines
        .where((line) => line.trimLeft().startsWith('Swap:'))
        .firstOrNull;
    final memParts = memLine?.trim().split(RegExp(r'\s+')) ?? const [];
    final swapParts = swapLine?.trim().split(RegExp(r'\s+')) ?? const [];
    final totalMemKb = _parseIntAt(memParts, 1);
    final usedMemKb = _parseIntAt(memParts, 2);
    final freeMemKb = _parseIntAt(
      memParts,
      3,
      fallback: max(0, totalMemKb - usedMemKb),
    );
    final totalSwapKb = _parseIntAt(swapParts, 1);
    final usedSwapKb = _parseIntAt(swapParts, 2);
    final freeSwapKb = _parseIntAt(
      swapParts,
      3,
      fallback: max(0, totalSwapKb - usedSwapKb),
    );
    return MemorySwapInfo(
      memInfo: MemoryInfo(
        totalMemMb: (totalMemKb / 1024).round(),
        usedMemMb: (usedMemKb / 1024).round(),
        freeMemMb: (freeMemKb / 1024).round(),
        usedMemPercentage: totalMemKb > 0
            ? _round2(usedMemKb / totalMemKb * 100)
            : 0,
        freeMemPercentage: totalMemKb > 0
            ? _round2(freeMemKb / totalMemKb * 100)
            : 0,
      ),
      swapInfo: SwapInfo(
        swapTotal: (totalSwapKb / 1024).round(),
        swapUsed: (usedSwapKb / 1024).round(),
        swapFree: (freeSwapKb / 1024).round(),
        swapPercentage: totalSwapKb > 0
            ? _round2(usedSwapKb / totalSwapKb * 100)
            : 0,
      ),
    );
  }

  // 解析 cgroup 内存/交换分区限制信息（一次命令拿全 5 行：
  // version, memTotal, memUsed, swapTotal, swapUsed）。
  // 容器化环境下 free -k 反映的是宿主机数据而非容器配额，需要 cgroup 数据来修正。
  // 返回 null 表示未容器化 / 权限不足 / 无法确定限制，调用方应继续用 free -k 的结果兜底。
  static CgroupMemoryInfo? parseCgroupMemory(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return null;
    final version = lines[0];
    if (version != 'v1' && version != 'v2') return null;
    if (lines.length < 5) return null;

    final memTotalRaw = lines[1];
    final memUsedRaw = lines[2];
    final swapTotalRaw = lines[3];
    final swapUsedRaw = lines[4];

    // 处理内存限制：v2 用 "max" 表示无限制；
    // v1 无限制时是接近 2^63 的哨兵值，用 1PB 阈值过滤掉
    int? memTotalBytes;
    int? memUsedBytes;
    if (memTotalRaw != 'max') {
      final t = int.tryParse(memTotalRaw);
      final u = int.tryParse(memUsedRaw);
      final isSentinel = version == 'v1' && t != null && t >= 1000000000000000;
      if (t != null && u != null && t > 0 && !isSentinel) {
        memTotalBytes = t;
        memUsedBytes = u;
      }
    }

    // 处理交换分区限制：只支持 cgroup v2 的 memory.swap.max/current（swap 专属限制）
    // v1 只有 memsw（内存+交换合并计数），需要减法推导且依赖内核 swapaccount 参数，
    // 可靠性不足，这里不做处理，交由 free -k 的宿主机数据兜底
    int? swapTotalBytes;
    int? swapUsedBytes;
    if (swapTotalRaw != 'max' && swapTotalRaw != 'na') {
      final t = int.tryParse(swapTotalRaw);
      final u = int.tryParse(swapUsedRaw);
      if (t != null && u != null && t > 0) {
        swapTotalBytes = t;
        swapUsedBytes = u;
      }
    }

    return CgroupMemoryInfo(
      memTotalBytes: memTotalBytes,
      memUsedBytes: memUsedBytes,
      swapTotalBytes: swapTotalBytes,
      swapUsedBytes: swapUsedBytes,
    );
  }

  // 若 cgroup 限制存在且明显比宿主机数据更小（说明确实被限制了），则以 cgroup 数据覆盖
  static MemorySwapInfo applyCgroupOverride(
    MemorySwapInfo hostInfo,
    CgroupMemoryInfo? cgroupInfo,
  ) {
    if (cgroupInfo == null) return hostInfo;

    var memInfo = hostInfo.memInfo;
    final memTotalBytes = cgroupInfo.memTotalBytes;
    final memUsedBytes = cgroupInfo.memUsedBytes;
    if (memTotalBytes != null && memUsedBytes != null) {
      final cgroupTotalMb = (memTotalBytes / 1024 / 1024).round();
      if (cgroupTotalMb > 0 && cgroupTotalMb < memInfo.totalMemMb) {
        final cgroupUsedMb = max(
          0,
          min((memUsedBytes / 1024 / 1024).round(), cgroupTotalMb),
        );
        final cgroupFreeMb = cgroupTotalMb - cgroupUsedMb;
        memInfo = MemoryInfo(
          totalMemMb: cgroupTotalMb,
          usedMemMb: cgroupUsedMb,
          freeMemMb: cgroupFreeMb,
          usedMemPercentage: _round2(cgroupUsedMb / cgroupTotalMb * 100),
          freeMemPercentage: _round2(cgroupFreeMb / cgroupTotalMb * 100),
        );
      }
    }

    var swapInfo = hostInfo.swapInfo;
    final swapTotalBytes = cgroupInfo.swapTotalBytes;
    final swapUsedBytes = cgroupInfo.swapUsedBytes;
    if (swapTotalBytes != null && swapUsedBytes != null) {
      final cgroupSwapTotalMb = (swapTotalBytes / 1024 / 1024).round();
      if (cgroupSwapTotalMb > 0 &&
          (swapInfo.swapTotal == 0 || cgroupSwapTotalMb < swapInfo.swapTotal)) {
        final cgroupSwapUsedMb = max(
          0,
          min((swapUsedBytes / 1024 / 1024).round(), cgroupSwapTotalMb),
        );
        swapInfo = SwapInfo(
          swapTotal: cgroupSwapTotalMb,
          swapUsed: cgroupSwapUsedMb,
          swapFree: cgroupSwapTotalMb - cgroupSwapUsedMb,
          swapPercentage: _round2(cgroupSwapUsedMb / cgroupSwapTotalMb * 100),
        );
      }
    }

    return MemorySwapInfo(memInfo: memInfo, swapInfo: swapInfo);
  }

  static List<DriveInfo> parseDrives(String output) {
    final drives = <DriveInfo>[];
    final lines = output.split('\n').skip(1);
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6) continue;
      final filesystem = parts[0];
      if (!filesystem.startsWith('/dev')) continue;
      final totalKb = int.tryParse(parts[1]) ?? 0;
      final usedKb = int.tryParse(parts[2]) ?? 0;
      final freeKb = int.tryParse(parts[3]) ?? 0;
      final totalGb = totalKb / 1024 / 1024;
      if (totalGb < 3) continue;
      final usedPercentage = double.tryParse(parts[4].replaceAll('%', '')) ?? 0;
      drives.add(
        DriveInfo(
          filesystem: filesystem,
          mountedOn: parts[5],
          totalGb: _round1(totalGb),
          usedGb: _round1(usedKb / 1024 / 1024),
          freeGb: _round1(freeKb / 1024 / 1024),
          usedPercentage: _round1(usedPercentage),
          freePercentage: _round1(100 - usedPercentage),
        ),
      );
    }
    return drives;
  }

  static NetworkCounters parseNetworkCounters(String output) {
    var rxBytes = 0;
    var txBytes = 0;
    final interfaces = <String, NetworkInterfaceCounters>{};
    for (final line in output.split('\n').skip(2)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 17) continue;
      final iface = parts[0].replaceAll(':', '');
      if (RegExp(r'^(lo|br-|docker|veth|virbr|tun|tap)').hasMatch(iface)) {
        continue;
      }
      final rx = int.tryParse(parts[1]) ?? 0;
      final tx = int.tryParse(parts[9]) ?? 0;
      rxBytes += rx;
      txBytes += tx;
      interfaces[iface] = NetworkInterfaceCounters(rxBytes: rx, txBytes: tx);
    }
    return NetworkCounters(
      rxBytes: rxBytes,
      txBytes: txBytes,
      interfaces: interfaces,
    );
  }

  static NetstatInfo networkRate({
    required NetworkCounters? previous,
    required NetworkCounters current,
    required DateTime? previousAt,
    required DateTime currentAt,
    required String? defaultInterface,
  }) {
    if (previous == null || previousAt == null) {
      return NetstatInfo(
        inputMb: 0,
        outputMb: 0,
        interfaceName: defaultInterface,
      );
    }
    final seconds = currentAt.difference(previousAt).inMilliseconds / 1000;
    if (seconds <= 0.1 || seconds > 10) {
      return NetstatInfo(
        inputMb: 0,
        outputMb: 0,
        interfaceName: defaultInterface,
      );
    }
    return NetstatInfo(
      inputMb: _round3(
        _safeDelta(current.rxBytes, previous.rxBytes) / seconds / 1024 / 1024,
      ),
      outputMb: _round3(
        _safeDelta(current.txBytes, previous.txBytes) / seconds / 1024 / 1024,
      ),
      interfaceName: defaultInterface,
    );
  }

  static OsInfo parseOsInfo({
    required String hostname,
    required String osRelease,
    required String arch,
    required String uptimeOutput,
  }) {
    var type = 'Linux';
    var release = 'Unknown';
    for (final line in osRelease.split('\n')) {
      if (line.startsWith('PRETTY_NAME=')) {
        final pretty = _unquote(line.replaceFirst('PRETTY_NAME=', ''));
        if (pretty.isNotEmpty) {
          type = pretty.split(' ').first;
          release =
              RegExp(r'(\d+\.?\d*\.?\d*)').firstMatch(pretty)?.group(1) ??
              release;
        }
      } else if (line.startsWith('NAME=')) {
        type = _unquote(line.replaceFirst('NAME=', '')).split(' ').first;
      } else if (line.startsWith('VERSION=')) {
        release = _unquote(line.replaceFirst('VERSION=', ''));
      }
    }
    final uptime =
        double.tryParse(uptimeOutput.trim().split(RegExp(r'\s+')).first) ?? 0;
    return OsInfo(
      hostname: hostname.trim().isEmpty ? 'Unknown' : hostname.trim(),
      type: type.trim().isEmpty ? 'Linux' : type.trim(),
      release: release.trim().isEmpty ? 'Unknown' : release.trim(),
      arch: arch.trim().isEmpty ? 'Unknown' : arch.trim(),
      uptime: uptime,
    );
  }

  static String parseCpuModel(String output) {
    final match = RegExp(r'model name\s*:\s*(.+)').firstMatch(output);
    return match?.group(1)?.trim().isNotEmpty == true
        ? match!.group(1)!.trim()
        : 'Unknown';
  }

  static int parseCpuCount(String output) {
    return int.tryParse(output.trim()) ?? 0;
  }

  static String? parseDefaultInterface(String output) {
    final value = output.trim().split(RegExp(r'\s+')).firstOrNull;
    return value == null || value.isEmpty ? null : value;
  }

  static int _parseIntAt(List<String> parts, int index, {int fallback = 0}) {
    if (index < 0 || index >= parts.length) return fallback;
    return int.tryParse(parts[index]) ?? fallback;
  }

  static int _safeDelta(int current, int previous) =>
      current >= previous ? current - previous : 0;

  static String _unquote(String value) => value.trim().replaceAll('"', '');

  static double _round1(double value) => double.parse(value.toStringAsFixed(1));
  static double _round2(double value) => double.parse(value.toStringAsFixed(2));
  static double _round3(double value) => double.parse(value.toStringAsFixed(3));
}

class MemorySwapInfo {
  const MemorySwapInfo({required this.memInfo, required this.swapInfo});

  final MemoryInfo memInfo;
  final SwapInfo swapInfo;
}

class CgroupMemoryInfo {
  const CgroupMemoryInfo({
    this.memTotalBytes,
    this.memUsedBytes,
    this.swapTotalBytes,
    this.swapUsedBytes,
  });

  final int? memTotalBytes;
  final int? memUsedBytes;
  final int? swapTotalBytes;
  final int? swapUsedBytes;
}
