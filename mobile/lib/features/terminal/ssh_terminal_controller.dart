import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import 'ssh_connection_config.dart';

/// Owns the dartssh2 client and bridges its stdio with an [xterm] [Terminal].
///
/// Connection flow:
/// - Open a TCP socket to the remote host.
/// - Build an [SSHClient] with either password or private key auth.
/// - Start a shell session and proxy bytes between the session and [terminal].
/// - Toolbar shortcuts feed [writeInput] which writes directly to the SSH
///   session (not the local terminal buffer) so the remote sees the keys.
class SshTerminalController {
  SshTerminalController({
    required this.config,
    Terminal? terminal,
  }) : terminal = terminal ?? Terminal();

  final SshConnectionConfig config;
  final Terminal terminal;

  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _disposed = false;

  Future<void> connect() async {
    if (_disposed) return;
    final socket = await SSHSocket.connect(config.host, config.port);
    // dartssh2 `SSHKeyPair.fromPem` already returns `List<SSHKeyPair>`, no extra
    // wrapping list needed.
    final identities = config.authType == 'privateKey'
        ? SSHKeyPair.fromPem(config.privateKey, config.passphrase)
        : null;
    _client = SSHClient(
      socket,
      username: config.username,
      onPasswordRequest: config.authType == 'password' ? () => config.password : null,
      identities: identities,
    );
    final session = await _client!.shell();
    _session = session;
    _stdoutSub = session.stdout.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    _stderrSub = session.stderr.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    terminal.onOutput = (data) {
      session.write(Uint8List.fromList(utf8.encode(data)));
    };
    terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      session.resizeTerminal(cols, rows);
    };
  }

  void resize(int columns, int rows) {
    _session?.resizeTerminal(columns, rows);
  }

  /// Send a raw escape sequence to the remote shell. Used by the toolbar
  /// buttons (Esc, Tab, Enter, etc.).
  void writeInput(String data) {
    _session?.write(Uint8List.fromList(utf8.encode(data)));
  }

  Future<void> disconnect() async {
    _disposed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
  }
}
