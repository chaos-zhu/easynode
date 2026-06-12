import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'ssh_connection_config.dart';
import 'ssh_transport.dart';

/// Owns the dartssh2 client and bridges its stdio with an [xterm] [Terminal].
///
/// Connection flow:
/// - Open a TCP socket to the remote host.
/// - Build an [SSHClient] with either password or private key auth.
/// - Start a shell session and proxy bytes between the session and [terminal].
/// - Toolbar shortcuts feed [writeInput] which writes directly to the SSH
///   session (not the local terminal buffer) so the remote sees the keys.
class SshTerminalController {
  static final RegExp _urlPattern = RegExp(
    r'((https?|ftp):\/\/[^\s<>"\u001b]+|www\.[^\s<>"\u001b]+)',
    caseSensitive: false,
  );

  SshTerminalController({
    required this.config,
    Terminal? terminal,
    SshTransportFactory? transportFactory,
  }) : terminal = terminal ?? Terminal(),
       _transportFactory = transportFactory ?? SshTransportFactory();

  final SshConnectionConfig config;
  final Terminal terminal;
  final SshTransportFactory _transportFactory;

  /// Whether the next single-letter input should be translated into Ctrl+letter.
  /// Lives on the controller (not the toolbar) so soft-keyboard input — which
  /// flows through `terminal.onOutput` directly — also consumes the modifier.
  final ValueNotifier<bool> ctrlPending = ValueNotifier<bool>(false);

  SSHClient? _client;
  SshTransportHandle? _transport;
  SSHSession? _session;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _disposed = false;

  Future<void> connect() async {
    if (_disposed) return;
    try {
      final transport = await _transportFactory.open(
        config,
        logger: (message) => terminal.write('[Info] $message\r\n'),
      );
      _transport = transport;
      terminal.write('[Info] 准备连接目标终端: ${config.name} - ${config.host}\r\n');
      // dartssh2 `SSHKeyPair.fromPem` already returns `List<SSHKeyPair>`, no
      // extra wrapping list needed.
      final identities = config.authType == 'privateKey'
          ? SSHKeyPair.fromPem(config.privateKey, config.privateKeyPassphrase)
          : null;
      _client = SSHClient(
        transport.socket,
        username: config.username,
        onPasswordRequest: config.authType == 'password'
            ? () => config.password
            : null,
        identities: identities,
      );
    } on SshTransportException catch (error) {
      terminal.write('[Error] ${error.message}\r\n');
      rethrow;
    } catch (error) {
      terminal.write('[Error] $error\r\n');
      rethrow;
    }
    final session = await _client!.shell();
    _session = session;
    _stdoutSub = session.stdout.listen((data) {
      _writeTerminalOutput(utf8.decode(data, allowMalformed: true));
    });
    _stderrSub = session.stderr.listen((data) {
      _writeTerminalOutput(utf8.decode(data, allowMalformed: true));
    });
    terminal.onOutput = (data) {
      final transformed = _applyCtrlIfPending(data);
      session.write(Uint8List.fromList(utf8.encode(transformed)));
    };
    terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      session.resizeTerminal(cols, rows);
    };
    // TerminalView may have already laid out and resized `terminal` before
    // shell() returned, in which case our onResize was null at the time and
    // the PTY is stuck at its default 80x24. Sync once now so vim/htop/less
    // pick up the real viewport instead of rendering into a half-screen.
    session.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
  }

  void resize(int columns, int rows) {
    _session?.resizeTerminal(columns, rows);
  }

  /// Send a raw escape sequence to the remote shell. Used by the toolbar
  /// buttons (Esc, Tab, arrows, etc.).
  void writeInput(String data) {
    final transformed = _applyCtrlIfPending(data);
    _session?.write(Uint8List.fromList(utf8.encode(transformed)));
  }

  void clearTerminal() {
    terminal.buffer.clear();
  }

  void _writeTerminalOutput(String text) {
    terminal.write(_decorateLinks(text));
  }

  String _decorateLinks(String text) {
    if (!_urlPattern.hasMatch(text)) return text;
    return text.replaceAllMapped(_urlPattern, (match) {
      final url = match.group(0)!;
      return '\x1b[4m$url\x1b[24m';
    });
  }

  void toggleCtrl() {
    ctrlPending.value = !ctrlPending.value;
  }

  String _applyCtrlIfPending(String data) {
    if (!ctrlPending.value || data.isEmpty) return data;
    ctrlPending.value = false;
    if (data.length != 1) return data;
    final code = data.toUpperCase().codeUnitAt(0);
    if (code >= 64 && code <= 95) {
      return String.fromCharCode(code - 64);
    }
    return data;
  }

  Future<void> disconnect() async {
    _disposed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _session?.close();
    _client?.close();
    await _transport?.close();
    _session = null;
    _client = null;
    _transport = null;
    ctrlPending.value = false;
  }
}
