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
    final totalMem = _parseIntAt(memParts, 1);
    final usedMem = _parseIntAt(memParts, 2);
    final freeMem = _parseIntAt(
      memParts,
      3,
      fallback: max(0, totalMem - usedMem),
    );
    final totalSwap = _parseIntAt(swapParts, 1);
    final usedSwap = _parseIntAt(swapParts, 2);
    final freeSwap = _parseIntAt(
      swapParts,
      3,
      fallback: max(0, totalSwap - usedSwap),
    );
    return MemorySwapInfo(
      memInfo: MemoryInfo(
        totalMemMb: totalMem,
        usedMemMb: usedMem,
        freeMemMb: freeMem,
        usedMemPercentage: totalMem > 0 ? _round2(usedMem / totalMem * 100) : 0,
        freeMemPercentage: totalMem > 0 ? _round2(freeMem / totalMem * 100) : 0,
      ),
      swapInfo: SwapInfo(
        swapTotal: totalSwap,
        swapUsed: usedSwap,
        swapFree: freeSwap,
        swapPercentage: totalSwap > 0 ? _round2(usedSwap / totalSwap * 100) : 0,
      ),
    );
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
