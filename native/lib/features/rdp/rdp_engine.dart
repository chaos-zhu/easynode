import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../terminal/ssh_connection_config.dart';
import 'rdp_tunnel.dart';

enum RdpQuality { low, medium, high }

class RdpOptions {
  const RdpOptions({
    this.resolution = 'adaptive',
    this.quality = RdpQuality.medium,
    this.clipboard = true,
  });
  final String resolution;
  final RdpQuality quality;
  final bool clipboard;

  List<String> arguments(SshConnectionConfig config, {int? tunnelPort}) {
    final host = config.host.contains(':') ? '[${config.host}]' : config.host;
    return [
      '/v:${tunnelPort == null ? '$host:${config.port}' : '127.0.0.1:$tunnelPort'}',
      '/u:${config.username}',
      '/t:EasyNode — ${config.name}',
      if (tunnelPort != null) ...[
        '/server-name:${config.host}',
        '/cert:name:${config.host}',
      ],
      '/size:${resolution == 'adaptive' ? '1280x800' : resolution}',
      if (resolution == 'adaptive') '+dynamic-resolution',
      '/network:${switch (quality) {
        RdpQuality.low => 'modem',
        RdpQuality.medium => 'broadband',
        RdpQuality.high => 'lan',
      }}',
      clipboard ? '+clipboard' : '-clipboard',
      '-auto-reconnect',
      '/log-level:ERROR',
    ];
  }
}

typedef RdpProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Runs only our bundled, patched SDL3 FreeRDP engine. No shell, .rdp files,
/// password arguments, environment credentials, or installed external clients.
class RdpEngine {
  RdpEngine({
    RdpProcessStarter? startProcess,
    Future<String> Function()? executable,
  }) : _startProcess = startProcess ?? _startBundledProcess,
       _executable = executable ?? bundledExecutable;
  final RdpProcessStarter _startProcess;
  final Future<String> Function() _executable;

  static Future<Process> _startBundledProcess(
    String exe,
    List<String> args,
  ) async {
    final support = await getApplicationSupportDirectory();
    final config = Directory(path.join(support.path, 'rdp'));
    await config.create(recursive: true);
    return Process.start(
      exe,
      args,
      environment: {'EASYNODE_RDP_CONFIG': config.path},
    );
  }

  static Future<String> bundledExecutable() async {
    final root = path.dirname(Platform.resolvedExecutable);
    final candidate = Platform.isMacOS
        ? path.normalize(path.join(root, '../Helpers/rdp/easynode-rdp'))
        : path.join(root, 'rdp', 'easynode-rdp.exe');
    if (!await File(candidate).exists()) {
      throw StateError(
        'RDP engine is not bundled. Run native/tools/rdp/build-${Platform.isMacOS ? 'macos.sh' : 'windows.ps1'} and rebuild EasyNode.',
      );
    }
    return candidate;
  }

  Future<RdpEngineWindow> open(
    SshConnectionConfig config,
    RdpOptions options,
  ) async {
    final executable = await _executable();
    RdpTunnel? tunnel;
    RdpEngineWindow? window;
    try {
      if (config.proxyType.isNotEmpty) tunnel = await RdpTunnel.open(config);
      final process = await _startProcess(
        executable,
        options.arguments(config, tunnelPort: tunnel?.port),
      );
      window = RdpEngineWindow(process, tunnel);
      // Binary length prefix, followed by UTF-8 password. Remaining stdin is a
      // small command channel. The helper exits when this pipe is closed.
      final password = Uint8List.fromList(utf8.encode(config.password));
      if (password.length > 65536) {
        await window.close();
        throw const FormatException('RDP password is too long');
      }
      final length = ByteData(4)..setUint32(0, password.length, Endian.big);
      try {
        process.stdin.add(length.buffer.asUint8List());
        process.stdin.add(password);
        await process.stdin.flush();
      } finally {
        password.fillRange(0, password.length, 0);
      }
      return window;
    } catch (_) {
      window?.terminate();
      await tunnel?.close();
      rethrow;
    }
  }
}

class RdpEngineWindow {
  RdpEngineWindow(this.process, this._tunnel) {
    _output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (line == 'EASYNODE_RDP connected') {
            _connected.completeIfPending(true);
          }
        }, onError: (Object _) {});
    // Drain logs without persisting or exposing raw engine messages.
    _errors = process.stderr.listen((_) {}, onError: (Object _) {});
    done = _wait();
  }
  final Process process;
  final RdpTunnel? _tunnel;
  final _connected = Completer<bool>();
  late final StreamSubscription<String> _output;
  late final StreamSubscription<List<int>> _errors;
  late final Future<int> done;
  Future<bool> get connected => _connected.future;
  bool _exited = false;
  Future<int> _wait() async {
    final code = await process.exitCode;
    _exited = true;
    _connected.completeIfPending(false);
    await _output.cancel();
    await _errors.cancel();
    await _tunnel?.close();
    return code;
  }

  Future<void> focus() async {
    if (!_exited) {
      process.stdin.writeln('focus');
      await process.stdin.flush();
    }
  }

  Future<void> close() async {
    if (_exited) return;
    try {
      process.stdin.writeln('close');
      await process.stdin.flush();
    } on IOException {
      /* The user may have already closed the native window. */
    }
    await done.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }

  void terminate() {
    if (!_exited) process.kill();
    unawaited(_tunnel?.close());
  }
}

extension on Completer<bool> {
  void completeIfPending(bool value) {
    if (!isCompleted) complete(value);
  }
}
