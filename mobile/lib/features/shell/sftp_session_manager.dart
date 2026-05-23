import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../servers/server_model.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/ssh_transport.dart';

enum SftpConnectionStatus { disconnected, connecting, connected, error }

class SftpFileEntry {
  const SftpFileEntry({
    required this.name,
    required this.type,
    required this.size,
    required this.modifyTime,
    required this.permissions,
    required this.ownerName,
    required this.groupName,
  });

  final String name;
  final String type;
  final int? size;
  final DateTime? modifyTime;
  final String permissions;
  final String ownerName;
  final String groupName;

  bool get isDirectory => type == 'd';
  bool get isLink => type == 'l';
}

class SftpFavorite {
  const SftpFavorite({
    required this.hostId,
    required this.path,
    required this.name,
    required this.type,
  });

  final String hostId;
  final String path;
  final String name;
  final String type;

  factory SftpFavorite.fromJson(Map<String, dynamic> json) {
    return SftpFavorite(
      hostId: (json['hostId'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }
}

class SftpSessionState extends ChangeNotifier {
  SftpSessionState({required this.server});

  final ServerModel server;
  SftpConnectionStatus status = SftpConnectionStatus.disconnected;
  String currentPath = '/';
  List<SftpFileEntry> entries = const [];
  List<SftpFavorite> favorites = const [];
  Set<String> selectedNames = <String>{};
  bool loadingDirectory = false;
  bool showHidden = false;
  String? lastError;

  bool get isConnected => status == SftpConnectionStatus.connected;
  bool get hasSelection => selectedNames.isNotEmpty;
  bool get allVisibleSelected =>
      entries.isNotEmpty &&
      entries.every((entry) => selectedNames.contains(entry.name));

  void update({
    SftpConnectionStatus? status,
    String? currentPath,
    List<SftpFileEntry>? entries,
    List<SftpFavorite>? favorites,
    Set<String>? selectedNames,
    bool? loadingDirectory,
    bool? showHidden,
    String? lastError,
  }) {
    if (status != null) this.status = status;
    if (currentPath != null) this.currentPath = currentPath;
    if (entries != null) this.entries = entries;
    if (favorites != null) this.favorites = favorites;
    if (selectedNames != null) this.selectedNames = selectedNames;
    if (loadingDirectory != null) this.loadingDirectory = loadingDirectory;
    if (showHidden != null) this.showHidden = showHidden;
    this.lastError = lastError;
    notifyListeners();
  }

  void toggleSelection(String name) {
    final next = Set<String>.from(selectedNames);
    if (!next.add(name)) next.remove(name);
    selectedNames = next;
    notifyListeners();
  }

  void addSelection(String name) {
    if (selectedNames.contains(name)) return;
    selectedNames = {...selectedNames, name};
    notifyListeners();
  }

  void selectOnly(String name) {
    selectedNames = {name};
    notifyListeners();
  }

  void toggleAllVisible() {
    if (allVisibleSelected) {
      selectedNames = <String>{};
    } else {
      selectedNames = entries.map((entry) => entry.name).toSet();
    }
    notifyListeners();
  }

  void clearSelection() {
    if (selectedNames.isEmpty) return;
    selectedNames = <String>{};
    notifyListeners();
  }
}

class SftpSessionManager extends ChangeNotifier {
  SftpSessionManager({SshTransportFactory? transportFactory})
    : _transportFactory = transportFactory ?? SshTransportFactory();

  final SshTransportFactory _transportFactory;
  final Map<String, _SftpConnection> _connections = {};
  final Map<String, SftpSessionState> _states = {};
  String? _activeHostId;

  Iterable<SftpSessionState> get sessions => List.unmodifiable(_states.values);
  String? get activeHostId => _activeHostId;
  SftpSessionState? get activeSession {
    final id = _activeHostId;
    return id == null ? null : _states[id];
  }

  bool isConnected(String hostId) {
    return _states[hostId]?.status == SftpConnectionStatus.connected;
  }

  SftpSessionState? sessionFor(String hostId) => _states[hostId];

  Future<SftpSessionState> connect({
    required ServerModel server,
    required SshConnectionConfig config,
    Future<List<SftpFavorite>> Function(String hostId)? loadFavorites,
  }) async {
    final existing = _states[server.id];
    if (existing?.status == SftpConnectionStatus.connected) {
      _activeHostId = server.id;
      notifyListeners();
      return existing!;
    }

    final state = existing ?? SftpSessionState(server: server);
    _states[server.id] = state;
    _activeHostId = server.id;
    state.update(
      status: SftpConnectionStatus.connecting,
      loadingDirectory: true,
      lastError: null,
      selectedNames: <String>{},
    );
    notifyListeners();

    try {
      await _connections.remove(server.id)?.close();
      final transport = await _transportFactory.open(config);
      final identities = config.authType == 'privateKey'
          ? SSHKeyPair.fromPem(config.privateKey, config.privateKeyPassphrase)
          : null;
      final client = SSHClient(
        transport.socket,
        username: config.username,
        onPasswordRequest: config.authType == 'password'
            ? () => config.password
            : null,
        identities: identities,
      );
      final sftp = await client.sftp();
      _connections[server.id] = _SftpConnection(
        client: client,
        sftp: sftp,
        transport: transport,
      );

      final initial = await _resolveInitialPath(sftp, config.username);
      final entries = await _listDirectory(sftp, initial, state.showHidden);
      final favorites = await loadFavorites?.call(server.id) ?? const [];
      state.update(
        status: SftpConnectionStatus.connected,
        currentPath: initial,
        entries: entries,
        favorites: favorites,
        loadingDirectory: false,
        lastError: null,
        selectedNames: <String>{},
      );
      notifyListeners();
      return state;
    } catch (error) {
      await _connections.remove(server.id)?.close();
      state.update(
        status: SftpConnectionStatus.error,
        loadingDirectory: false,
        lastError: error.toString(),
      );
      notifyListeners();
      rethrow;
    }
  }

  void activate(String hostId) {
    if (_states[hostId] == null) return;
    _activeHostId = hostId;
    notifyListeners();
  }

  Future<void> disconnectActive() async {
    final hostId = _activeHostId;
    if (hostId == null) return;
    final connection = _connections.remove(hostId);
    final state = _states.remove(hostId);
    await connection?.close();
    state?.dispose();
    _activeHostId = _states.isEmpty ? null : _states.keys.first;
    notifyListeners();
  }

  Future<void> openPath(String path) async {
    final state = activeSession;
    if (state == null) return;
    final connection = _connections[state.server.id];
    if (connection == null) return;
    state.update(loadingDirectory: true, lastError: null);
    try {
      final entries = await _listDirectory(
        connection.sftp,
        path,
        state.showHidden,
      );
      state.update(
        currentPath: path,
        entries: entries,
        loadingDirectory: false,
        selectedNames: <String>{},
      );
    } catch (error) {
      state.update(loadingDirectory: false, lastError: error.toString());
    }
  }

  Future<void> refreshActive() async {
    final path = activeSession?.currentPath;
    if (path == null) return;
    await openPath(path);
  }

  Future<void> createDirectory(String name) async {
    final state = activeSession;
    if (state == null) return;
    final connection = _connections[state.server.id];
    if (connection == null) return;
    final targetPath = joinPath(state.currentPath, name.trim());
    await connection.sftp.mkdir(targetPath);
    await refreshActive();
  }

  Future<void> createFile(String name) async {
    final state = activeSession;
    if (state == null) return;
    final connection = _connections[state.server.id];
    if (connection == null) return;
    final targetPath = joinPath(state.currentPath, name.trim());
    final file = await connection.sftp.open(
      targetPath,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.exclusive,
    );
    try {
      await file.writeBytes(Uint8List(0));
    } finally {
      await file.close();
    }
    await refreshActive();
  }

  Future<void> goParent() async {
    final state = activeSession;
    if (state == null) return;
    await openPath(parentPath(state.currentPath));
  }

  Future<void> setShowHidden(bool value) async {
    final state = activeSession;
    if (state == null || state.showHidden == value) return;
    state.update(showHidden: value);
    await refreshActive();
  }

  String entryPath(SftpSessionState state, SftpFileEntry entry) {
    return joinPath(state.currentPath, entry.name);
  }

  static String joinPath(String base, String name) {
    if (base == '/' || base == '~') return '$base/$name'.replaceAll('//', '/');
    if (base.endsWith('/')) return '$base$name';
    return '$base/$name';
  }

  static String parentPath(String path) {
    if (path == '/' || path == '~') return path;
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index);
  }

  @override
  void dispose() {
    for (final connection in _connections.values) {
      unawaited(connection.close());
    }
    for (final state in _states.values) {
      state.dispose();
    }
    _connections.clear();
    _states.clear();
    super.dispose();
  }

  Future<String> _resolveInitialPath(SftpClient sftp, String username) async {
    if (username == 'root') {
      try {
        await sftp.listdir('/root');
        return '/root';
      } catch (_) {
        return '/';
      }
    }
    try {
      await sftp.listdir('/');
      return '/';
    } catch (_) {
      try {
        return await sftp.absolute('.');
      } catch (_) {
        return '~';
      }
    }
  }

  Future<List<SftpFileEntry>> _listDirectory(
    SftpClient sftp,
    String path,
    bool showHidden,
  ) async {
    final names = await sftp.listdir(path == '~' ? '.' : path);
    final entries = names
        .where((item) => item.filename != '.' && item.filename != '..')
        .where((item) => showHidden || !item.filename.startsWith('.'))
        .map(_entryFromName)
        .toList(growable: false);
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  SftpFileEntry _entryFromName(SftpName name) {
    final type = _typeFromLongName(name.longname);
    final parts = name.longname.trim().split(RegExp(r'\s+'));
    final permissions = parts.isNotEmpty ? parts.first.skip(1) : '';
    final ownerName = parts.length >= 3 ? parts[2] : '';
    final groupName = parts.length >= 4 ? parts[3] : '';
    return SftpFileEntry(
      name: name.filename,
      type: type,
      size: name.attr.size,
      modifyTime: _dateFromSeconds(name.attr.modifyTime),
      permissions: permissions,
      ownerName: ownerName,
      groupName: groupName,
    );
  }

  String _typeFromLongName(String longName) {
    if (longName.startsWith('d')) return 'd';
    if (longName.startsWith('l')) return 'l';
    return '-';
  }

  DateTime? _dateFromSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}

class _SftpConnection {
  _SftpConnection({
    required this.client,
    required this.sftp,
    required this.transport,
  });

  final SSHClient client;
  final SftpClient sftp;
  final SshTransportHandle transport;

  Future<void> close() async {
    sftp.close();
    client.close();
    await transport.close();
  }
}

extension on String {
  String skip(int count) {
    if (length <= count) return '';
    return substring(count);
  }
}
