# Mobile Native Proxy and Jump Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mobile-local SOCKS5 proxy and SSH jump-host support for native terminal connections without routing mobile sessions through the server terminal websocket.

**Architecture:** The server expands the encrypted `/mobile/ssh-connection` payload with proxy and jump-host topology. Mobile parses that payload into focused config models, builds the final `SSHSocket` through a transport factory, then creates the existing `SSHClient` over that socket. Direct connections stay behaviorally unchanged.

**Tech Stack:** Node.js server controllers/tests, Flutter/Dart mobile app, `dartssh2 2.14.0`, `flutter_test`, Node `assert`.

---

## File Structure

- Modify: `server/app/controller/mobile.js`
  - Keep `toMobileSshPayload` as the pure payload builder used by tests.
  - Add topology arguments for `proxyType`, `proxy`, and `jumpHosts`.
  - Add async helpers used by `getMobileSshConnection` to resolve proxy and jump-host connection details.
- Modify: `server/test/test-mobile-ssh-payload.js`
  - Extend existing pure payload tests for direct, SOCKS5, jump-host, invalid auth, invalid proxy type, and missing topology.
- Modify: `mobile/lib/features/terminal/ssh_connection_config.dart`
  - Add target auth helper shape plus `SshProxyConfig` and `SshJumpHostConfig`.
  - Preserve empty-passphrase-to-null behavior for target and jump-host private keys.
- Modify: `mobile/test/features/terminal/ssh_connection_config_test.dart`
  - Cover direct, SOCKS5, jump-host parsing, invalid port fallback, and passphrase normalization.
- Create: `mobile/lib/features/terminal/ssh_transport.dart`
  - Define `SshTransportHandle`, `SshTransportFactory`, `SshClientFactory`, and `SshTransportException`.
  - Implement direct transport first, then SOCKS5 and jump-host branches.
- Create: `mobile/lib/features/terminal/socks5_connector.dart`
  - Implement the SOCKS5 TCP negotiation over a native `Socket`.
  - Return an `SSHSocket` adapter for `dartssh2`.
- Create: `mobile/test/features/terminal/socks5_connector_test.dart`
  - Use a local `ServerSocket` to assert SOCKS5 no-auth and username/password handshakes.
- Modify: `mobile/lib/features/terminal/ssh_terminal_controller.dart`
  - Replace direct `SSHSocket.connect` with `SshTransportFactory.open`.
  - Close the transport handle when disconnecting.
- Create: `mobile/test/features/terminal/ssh_transport_test.dart`
  - Verify factory selection, unsupported proxy errors, direct socket creation, and jump-host lifecycle through fakes.

## Task 1: Server Mobile Payload Topology

**Files:**
- Modify: `server/app/controller/mobile.js`
- Modify: `server/test/test-mobile-ssh-payload.js`

- [ ] **Step 1: Write failing server payload tests**

Replace `server/test/test-mobile-ssh-payload.js` with:

```js
const assert = require('assert')
const { toMobileSshPayload } = require('../app/controller/mobile')

function testPasswordPayload() {
  const payload = toMobileSshPayload('h1', 'prod', {
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'p@ss'
  })

  assert.deepStrictEqual(payload, {
    hostId: 'h1',
    name: 'prod',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'p@ss',
    privateKey: '',
    passphrase: '',
    proxyType: '',
    proxy: null,
    jumpHosts: []
  })
}

function testPrivateKeyPayload() {
  const payload = toMobileSshPayload('h2', 'keyhost', {
    host: '10.0.0.3',
    port: 2222,
    username: 'ubuntu',
    authType: 'privateKey',
    privateKey: 'KEY',
    passphrase: 'phrase'
  })

  assert.strictEqual(payload.authType, 'privateKey')
  assert.strictEqual(payload.privateKey, 'KEY')
  assert.strictEqual(payload.password, '')
  assert.strictEqual(payload.passphrase, 'phrase')
  assert.strictEqual(payload.proxyType, '')
  assert.strictEqual(payload.proxy, null)
  assert.deepStrictEqual(payload.jumpHosts, [])
}

function testSocks5ProxyPayload() {
  const payload = toMobileSshPayload('h3', 'proxied', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret'
  }, {
    proxyType: 'proxyServer',
    proxy: {
      id: 'p1',
      name: 'office',
      type: 'socks5',
      host: '127.0.0.1',
      port: 1080,
      username: 'u',
      password: 'p'
    }
  })

  assert.strictEqual(payload.proxyType, 'proxyServer')
  assert.deepStrictEqual(payload.proxy, {
    id: 'p1',
    name: 'office',
    type: 'socks5',
    host: '127.0.0.1',
    port: 1080,
    username: 'u',
    password: 'p'
  })
  assert.deepStrictEqual(payload.jumpHosts, [])
}

function testJumpHostPayload() {
  const payload = toMobileSshPayload('h4', 'target', {
    host: '10.0.0.20',
    port: 22,
    username: 'root',
    authType: 'privateKey',
    privateKey: 'TARGET_KEY'
  }, {
    proxyType: 'jumpHosts',
    jumpHosts: [{
      hostId: 'j1',
      name: 'jump-1',
      host: '203.0.113.10',
      port: 22,
      username: 'root',
      authType: 'password',
      password: 'jump-secret'
    }]
  })

  assert.strictEqual(payload.proxyType, 'jumpHosts')
  assert.strictEqual(payload.proxy, null)
  assert.deepStrictEqual(payload.jumpHosts, [{
    hostId: 'j1',
    name: 'jump-1',
    host: '203.0.113.10',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'jump-secret',
    privateKey: '',
    passphrase: ''
  }])
}

function testRejectsUnsupportedAuth() {
  assert.throws(() => toMobileSshPayload('h5', 'unsupported', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'keyboard'
  }), /unsupported mobile ssh auth type/)
}

function testRejectsUnsupportedProxyType() {
  assert.throws(() => toMobileSshPayload('h6', 'bad-proxy', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret'
  }, {
    proxyType: 'proxyServer',
    proxy: {
      id: 'p1',
      name: 'http-only',
      type: 'http',
      host: '127.0.0.1',
      port: 8080
    }
  }), /unsupported mobile proxy type: http/)
}

function testRejectsMissingJumpHosts() {
  assert.throws(() => toMobileSshPayload('h7', 'missing-jump', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret'
  }, {
    proxyType: 'jumpHosts',
    jumpHosts: []
  }), /mobile jump host chain is empty/)
}

testPasswordPayload()
testPrivateKeyPayload()
testSocks5ProxyPayload()
testJumpHostPayload()
testRejectsUnsupportedAuth()
testRejectsUnsupportedProxyType()
testRejectsMissingJumpHosts()
console.log('test-mobile-ssh-payload passed')
```

- [ ] **Step 2: Run the failing server test**

Run:

```bash
node server/test/test-mobile-ssh-payload.js
```

Expected: FAIL because `proxyType`, `proxy`, and `jumpHosts` are not included yet.

- [ ] **Step 3: Implement pure payload builder**

In `server/app/controller/mobile.js`, update `toMobileSshPayload` and add these helpers above it:

```js
function normalizePort(port) {
  const numericPort = Number(port)
  return Number.isFinite(numericPort) && numericPort > 0 ? numericPort : 22
}

function normalizeMobileAuthPayload(hostId, name, authInfo) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported mobile ssh auth type: ${ authType || 'empty' }`)
  }

  return {
    hostId,
    name,
    host,
    port: normalizePort(port),
    username,
    authType,
    password: authType === 'password' ? authInfo.password || '' : '',
    privateKey: authType === 'privateKey' ? authInfo.privateKey || '' : '',
    passphrase: authType === 'privateKey' ? authInfo.passphrase || '' : ''
  }
}

function normalizeMobileProxy(proxy) {
  if (!proxy) return null
  if (proxy.type !== 'socks5') {
    throw new Error(`unsupported mobile proxy type: ${ proxy.type || 'empty' }`)
  }
  return {
    id: proxy.id || proxy._id || '',
    name: proxy.name || '',
    type: proxy.type,
    host: proxy.host,
    port: normalizePort(proxy.port),
    username: proxy.username || '',
    password: proxy.password || ''
  }
}
```

Then replace `toMobileSshPayload` with:

```js
function toMobileSshPayload(hostId, name, authInfo, topology = {}) {
  const proxyType = topology.proxyType || ''
  const proxy = proxyType === 'proxyServer' ? normalizeMobileProxy(topology.proxy) : null
  const jumpHosts = proxyType === 'jumpHosts'
    ? (topology.jumpHosts || []).map((jumpHost) => normalizeMobileAuthPayload(
      jumpHost.hostId || jumpHost.id || '',
      jumpHost.name || '',
      jumpHost
    ))
    : []

  if (proxyType === 'proxyServer' && !proxy) {
    throw new Error('mobile proxy config is missing')
  }
  if (proxyType === 'jumpHosts' && jumpHosts.length === 0) {
    throw new Error('mobile jump host chain is empty')
  }
  if (proxyType && !['proxyServer', 'jumpHosts'].includes(proxyType)) {
    throw new Error(`unsupported mobile proxy type: ${ proxyType }`)
  }

  return {
    ...normalizeMobileAuthPayload(hostId, name, authInfo),
    proxyType,
    proxy,
    jumpHosts
  }
}
```

- [ ] **Step 4: Add async topology resolution for real API**

In `server/app/controller/mobile.js`, add below `toMobileSshPayload`:

```js
async function getMobileConnectionTopology(hostInfo) {
  const { proxyType, proxyServer, jumpHosts } = hostInfo
  if (proxyType === 'proxyServer') {
    const { getProxyConfig } = require('../socket/terminal')
    const proxy = await getProxyConfig(proxyServer)
    return { proxyType, proxy, jumpHosts: [] }
  }

  if (proxyType === 'jumpHosts') {
    if (!Array.isArray(jumpHosts) || jumpHosts.length === 0) {
      throw new Error('mobile jump host chain is empty')
    }
    const { getConnectionOptions } = require('../socket/terminal')
    const resolvedJumpHosts = []
    for (const jumpHostId of jumpHosts) {
      const { authInfo, name } = await getConnectionOptions(jumpHostId)
      resolvedJumpHosts.push({
        hostId: jumpHostId,
        name,
        ...authInfo
      })
    }
    return { proxyType, proxy: null, jumpHosts: resolvedJumpHosts }
  }

  return { proxyType: '', proxy: null, jumpHosts: [] }
}
```

Then update `getMobileSshConnection` to read the host record and pass topology:

```js
const { HostListDB } = require('../utils/db-class')
const hostListDB = new HostListDB().getInstance()
```

Inside the handler, after `getConnectionOptions(hostId)`:

```js
const hostInfo = await hostListDB.findOneAsync({ _id: hostId })
if (!hostInfo) throw new Error(`Host with ID ${ hostId } not found`)
const topology = await getMobileConnectionTopology(hostInfo)
const payload = toMobileSshPayload(hostId, name, authInfo, topology)
```

- [ ] **Step 5: Run server test and commit**

Run:

```bash
node server/test/test-mobile-ssh-payload.js
```

Expected: PASS with `test-mobile-ssh-payload passed`.

Commit:

```bash
git add server/app/controller/mobile.js server/test/test-mobile-ssh-payload.js
git commit -m "feat: include mobile ssh connection topology"
```

## Task 2: Mobile SSH Config Models

**Files:**
- Modify: `mobile/lib/features/terminal/ssh_connection_config.dart`
- Modify: `mobile/test/features/terminal/ssh_connection_config_test.dart`

- [ ] **Step 1: Replace config tests with model coverage**

Replace `mobile/test/features/terminal/ssh_connection_config_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';

void main() {
  Map<String, dynamic> basePayload({String passphrase = ''}) => {
        'hostId': 'h1',
        'name': 'prod',
        'host': '10.0.0.2',
        'port': 22,
        'username': 'root',
        'authType': 'privateKey',
        'password': '',
        'privateKey': 'key',
        'passphrase': passphrase,
        'proxyType': '',
        'proxy': null,
        'jumpHosts': [],
      };

  test('parses direct payload and normalizes empty passphrase', () {
    final config = SshConnectionConfig.fromJson(basePayload(passphrase: '   '));

    expect(config.hostId, 'h1');
    expect(config.port, 22);
    expect(config.proxyType, '');
    expect(config.proxy, isNull);
    expect(config.jumpHosts, isEmpty);
    expect(config.privateKeyPassphrase, isNull);
  });

  test('keeps non-empty private key passphrase', () {
    final config = SshConnectionConfig.fromJson(basePayload(passphrase: ' secret '));

    expect(config.privateKeyPassphrase, 'secret');
  });

  test('parses socks5 proxy payload', () {
    final config = SshConnectionConfig.fromJson({
      ...basePayload(),
      'proxyType': 'proxyServer',
      'proxy': {
        'id': 'p1',
        'name': 'office',
        'type': 'socks5',
        'host': '127.0.0.1',
        'port': '1080',
        'username': 'u',
        'password': 'p',
      },
    });

    expect(config.proxyType, 'proxyServer');
    expect(config.proxy!.id, 'p1');
    expect(config.proxy!.port, 1080);
    expect(config.proxy!.username, 'u');
  });

  test('parses jump host payload and normalizes jump passphrase', () {
    final config = SshConnectionConfig.fromJson({
      ...basePayload(),
      'proxyType': 'jumpHosts',
      'jumpHosts': [
        {
          'hostId': 'j1',
          'name': 'jump',
          'host': '203.0.113.10',
          'port': 2200,
          'username': 'root',
          'authType': 'privateKey',
          'password': '',
          'privateKey': 'jump-key',
          'passphrase': '',
        }
      ],
    });

    expect(config.jumpHosts, hasLength(1));
    expect(config.jumpHosts.single.hostId, 'j1');
    expect(config.jumpHosts.single.port, 2200);
    expect(config.jumpHosts.single.privateKeyPassphrase, isNull);
  });
}
```

- [ ] **Step 2: Run the failing mobile config test**

Run:

```bash
cd mobile
flutter test test/features/terminal/ssh_connection_config_test.dart
```

Expected: FAIL because `proxyType`, `proxy`, `jumpHosts`, `SshProxyConfig`, and `SshJumpHostConfig` do not exist yet.

- [ ] **Step 3: Implement config models**

Replace `mobile/lib/features/terminal/ssh_connection_config.dart` with:

```dart
class SshAuthConfig {
  const SshAuthConfig({
    required this.hostId,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.password,
    required this.privateKey,
    required this.passphrase,
  });

  final String hostId;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String password;
  final String privateKey;
  final String passphrase;

  String? get privateKeyPassphrase {
    final trimmed = passphrase.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static SshAuthConfig fromJson(Map<String, dynamic> json) {
    return SshAuthConfig(
      hostId: (json['hostId'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: _parsePort(json['port']),
      username: (json['username'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      privateKey: (json['privateKey'] ?? '').toString(),
      passphrase: (json['passphrase'] ?? '').toString(),
    );
  }
}

class SshProxyConfig {
  const SshProxyConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String id;
  final String name;
  final String type;
  final String host;
  final int port;
  final String username;
  final String password;

  factory SshProxyConfig.fromJson(Map<String, dynamic> json) {
    return SshProxyConfig(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: _parsePort(json['port']),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }
}

class SshJumpHostConfig extends SshAuthConfig {
  const SshJumpHostConfig({
    required super.hostId,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.authType,
    required super.password,
    required super.privateKey,
    required super.passphrase,
  });

  factory SshJumpHostConfig.fromJson(Map<String, dynamic> json) {
    final auth = SshAuthConfig.fromJson(json);
    return SshJumpHostConfig(
      hostId: auth.hostId,
      name: auth.name,
      host: auth.host,
      port: auth.port,
      username: auth.username,
      authType: auth.authType,
      password: auth.password,
      privateKey: auth.privateKey,
      passphrase: auth.passphrase,
    );
  }
}

class SshConnectionConfig extends SshAuthConfig {
  const SshConnectionConfig({
    required super.hostId,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.authType,
    required super.password,
    required super.privateKey,
    required super.passphrase,
    required this.proxyType,
    required this.proxy,
    required this.jumpHosts,
  });

  final String proxyType;
  final SshProxyConfig? proxy;
  final List<SshJumpHostConfig> jumpHosts;

  factory SshConnectionConfig.fromJson(Map<String, dynamic> json) {
    final auth = SshAuthConfig.fromJson(json);
    final proxyRaw = json['proxy'];
    final jumpHostsRaw = json['jumpHosts'];
    return SshConnectionConfig(
      hostId: auth.hostId,
      name: auth.name,
      host: auth.host,
      port: auth.port,
      username: auth.username,
      authType: auth.authType,
      password: auth.password,
      privateKey: auth.privateKey,
      passphrase: auth.passphrase,
      proxyType: (json['proxyType'] ?? '').toString(),
      proxy: proxyRaw is Map<String, dynamic>
          ? SshProxyConfig.fromJson(proxyRaw)
          : null,
      jumpHosts: jumpHostsRaw is List
          ? jumpHostsRaw
              .whereType<Map<String, dynamic>>()
              .map(SshJumpHostConfig.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

int _parsePort(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 22;
}
```

- [ ] **Step 4: Run mobile config test and commit**

Run:

```bash
cd mobile
dart format lib/features/terminal/ssh_connection_config.dart test/features/terminal/ssh_connection_config_test.dart
flutter test test/features/terminal/ssh_connection_config_test.dart
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/features/terminal/ssh_connection_config.dart mobile/test/features/terminal/ssh_connection_config_test.dart
git commit -m "feat: parse mobile ssh topology config"
```

## Task 3: Direct Transport Abstraction

**Files:**
- Create: `mobile/lib/features/terminal/ssh_transport.dart`
- Modify: `mobile/lib/features/terminal/ssh_terminal_controller.dart`
- Create: `mobile/test/features/terminal/ssh_transport_test.dart`

- [ ] **Step 1: Write failing direct transport tests**

Create `mobile/test/features/terminal/ssh_transport_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/ssh_connection_config.dart';
import 'package:mobile/features/terminal/ssh_transport.dart';

class FakeSocket implements SSHSocket {
  FakeSocket(this.label);
  final String label;
  bool closed = false;

  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done async {}

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void destroy() {
    closed = true;
  }
}

SshConnectionConfig config({String proxyType = ''}) {
  return SshConnectionConfig(
    hostId: 'h1',
    name: 'prod',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret',
    privateKey: '',
    passphrase: '',
    proxyType: proxyType,
    proxy: null,
    jumpHosts: const [],
  );
}

void main() {
  test('opens direct transport when proxyType is empty', () async {
    final calls = <String>[];
    final socket = FakeSocket('target');
    final factory = SshTransportFactory(
      connectSocket: (host, port) async {
        calls.add('$host:$port');
        return socket;
      },
    );

    final handle = await factory.open(config());

    expect(calls, ['10.0.0.2:22']);
    expect(handle.socket, same(socket));
    await handle.close();
    expect(socket.closed, isTrue);
  });

  test('fails explicitly for unsupported proxyType', () async {
    final factory = SshTransportFactory(
      connectSocket: (host, port) async => FakeSocket('unused'),
    );

    expect(
      () => factory.open(config(proxyType: 'unknown')),
      throwsA(isA<SshTransportException>().having(
        (error) => error.message,
        'message',
        'Unsupported mobile proxy type: unknown',
      )),
    );
  });
}
```

- [ ] **Step 2: Run the failing direct transport test**

Run:

```bash
cd mobile
flutter test test/features/terminal/ssh_transport_test.dart
```

Expected: FAIL because `ssh_transport.dart` does not exist.

- [ ] **Step 3: Implement direct transport abstraction**

Create `mobile/lib/features/terminal/ssh_transport.dart`:

```dart
import 'package:dartssh2/dartssh2.dart';

import 'ssh_connection_config.dart';

typedef SshSocketConnector = Future<SSHSocket> Function(String host, int port);

class SshTransportException implements Exception {
  const SshTransportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SshTransportHandle {
  SshTransportHandle({
    required this.socket,
    required List<SSHClient> intermediateClients,
  }) : _intermediateClients = intermediateClients;

  final SSHSocket socket;
  final List<SSHClient> _intermediateClients;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final client in _intermediateClients.reversed) {
      client.close();
    }
    await socket.close();
  }
}

class SshTransportFactory {
  SshTransportFactory({
    SshSocketConnector? connectSocket,
  }) : _connectSocket = connectSocket ?? SSHSocket.connect;

  final SshSocketConnector _connectSocket;

  Future<SshTransportHandle> open(SshConnectionConfig config) async {
    if (config.proxyType.isEmpty) {
      final socket = await _connectSocket(config.host, config.port);
      return SshTransportHandle(socket: socket, intermediateClients: const []);
    }

    throw SshTransportException(
      'Unsupported mobile proxy type: ${config.proxyType}',
    );
  }
}
```

- [ ] **Step 4: Migrate controller to transport factory**

In `mobile/lib/features/terminal/ssh_terminal_controller.dart`:

Add import:

```dart
import 'ssh_transport.dart';
```

Update constructor and fields:

```dart
SshTerminalController({
  required this.config,
  Terminal? terminal,
  SshTransportFactory? transportFactory,
})  : terminal = terminal ?? Terminal(),
      _transportFactory = transportFactory ?? SshTransportFactory();

final SshTransportFactory _transportFactory;
SshTransportHandle? _transport;
```

Replace the direct socket line in `connect()`:

```dart
final transport = await _transportFactory.open(config);
_transport = transport;
```

Then pass `transport.socket` into `SSHClient`:

```dart
_client = SSHClient(
  transport.socket,
  username: config.username,
  onPasswordRequest: config.authType == 'password' ? () => config.password : null,
  identities: identities,
);
```

In `disconnect()`, after `_client?.close();`, add:

```dart
await _transport?.close();
_transport = null;
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
cd mobile
dart format lib/features/terminal/ssh_transport.dart lib/features/terminal/ssh_terminal_controller.dart test/features/terminal/ssh_transport_test.dart
flutter test test/features/terminal
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/features/terminal/ssh_transport.dart mobile/lib/features/terminal/ssh_terminal_controller.dart mobile/test/features/terminal/ssh_transport_test.dart
git commit -m "feat: add mobile ssh transport abstraction"
```

## Task 4: SOCKS5 Transport

**Files:**
- Create: `mobile/lib/features/terminal/socks5_connector.dart`
- Modify: `mobile/lib/features/terminal/ssh_transport.dart`
- Create: `mobile/test/features/terminal/socks5_connector_test.dart`
- Modify: `mobile/test/features/terminal/ssh_transport_test.dart`

- [ ] **Step 1: Write SOCKS5 connector tests**

Create `mobile/test/features/terminal/socks5_connector_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/terminal/socks5_connector.dart';

Future<List<int>> readExactly(Socket socket, int length) async {
  final bytes = <int>[];
  final sub = socket.listen(bytes.addAll);
  while (bytes.length < length) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await sub.cancel();
  return bytes.take(length).toList();
}

void main() {
  test('performs no-auth socks5 handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final captured = <List<int>>[];

    unawaited(server.first.then((socket) async {
      captured.add(await readExactly(socket, 3));
      socket.add([0x05, 0x00]);
      captured.add(await readExactly(socket, 18));
      socket.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]);
    }));

    final connector = Socks5Connector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
    );

    expect(captured.first, [0x05, 0x01, 0x00]);
    expect(captured.last.take(5), [0x05, 0x01, 0x00, 0x03, 11]);
    await socket.close();
    await server.close();
  });

  test('performs username password socks5 handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final captured = <List<int>>[];

    unawaited(server.first.then((socket) async {
      captured.add(await readExactly(socket, 4));
      socket.add([0x05, 0x02]);
      captured.add(await readExactly(socket, 5));
      socket.add([0x01, 0x00]);
      captured.add(await readExactly(socket, 18));
      socket.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]);
    }));

    final connector = Socks5Connector();
    final socket = await connector.connect(
      proxyHost: '127.0.0.1',
      proxyPort: server.port,
      targetHost: 'example.com',
      targetPort: 22,
      username: 'u',
      password: 'p',
    );

    expect(captured.first, [0x05, 0x02, 0x00, 0x02]);
    expect(captured[1], [0x01, 0x01, 117, 0x01, 112]);
    await socket.close();
    await server.close();
  });
}
```

- [ ] **Step 2: Run the failing SOCKS5 test**

Run:

```bash
cd mobile
flutter test test/features/terminal/socks5_connector_test.dart
```

Expected: FAIL because `socks5_connector.dart` does not exist.

- [ ] **Step 3: Implement SOCKS5 connector**

Create `mobile/lib/features/terminal/socks5_connector.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_transport.dart';

class SocketSshSocket implements SSHSocket {
  SocketSshSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket.map(Uint8List.fromList);

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() {
    _socket.destroy();
  }
}

class Socks5Connector {
  Future<SSHSocket> connect({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String username = '',
    String password = '',
  }) async {
    final socket = await Socket.connect(proxyHost, proxyPort);
    final iterator = StreamIterator<List<int>>(socket);
    try {
      final wantsAuth = username.isNotEmpty || password.isNotEmpty;
      socket.add(wantsAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]);
      final method = await _readExactly(iterator, 2);
      if (method[0] != 0x05) {
        throw const SshTransportException('SOCKS5 proxy connection failed');
      }
      if (method[1] == 0xFF) {
        throw const SshTransportException('SOCKS5 authentication failed');
      }
      if (method[1] == 0x02) {
        await _authenticate(socket, iterator, username, password);
      }

      socket.add(_connectRequest(targetHost, targetPort));
      final response = await _readExactly(iterator, 5);
      if (response[1] != 0x00) {
        throw const SshTransportException('SOCKS5 target connection failed');
      }
      final addressLength = switch (response[3]) {
        0x01 => 4,
        0x03 => response[4],
        0x04 => 16,
        _ => throw const SshTransportException('SOCKS5 target connection failed'),
      };
      if (response[3] == 0x03) {
        await _readExactly(iterator, addressLength + 2);
      } else {
        await _readExactly(iterator, addressLength - 1 + 2);
      }
      return SocketSshSocket(socket);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> _authenticate(
    Socket socket,
    StreamIterator<List<int>> iterator,
    String username,
    String password,
  ) async {
    final user = utf8.encode(username);
    final pass = utf8.encode(password);
    socket.add([0x01, user.length, ...user, pass.length, ...pass]);
    final response = await _readExactly(iterator, 2);
    if (response[1] != 0x00) {
      throw const SshTransportException('SOCKS5 authentication failed');
    }
  }

  List<int> _connectRequest(String host, int port) {
    final hostBytes = utf8.encode(host);
    return [
      0x05,
      0x01,
      0x00,
      0x03,
      hostBytes.length,
      ...hostBytes,
      (port >> 8) & 0xFF,
      port & 0xFF,
    ];
  }

  Future<List<int>> _readExactly(
    StreamIterator<List<int>> iterator,
    int length,
  ) async {
    final bytes = <int>[];
    while (bytes.length < length && await iterator.moveNext()) {
      bytes.addAll(iterator.current);
    }
    if (bytes.length < length) {
      throw const SshTransportException('SOCKS5 proxy connection failed');
    }
    return bytes.take(length).toList();
  }
}
```

- [ ] **Step 4: Wire SOCKS5 transport into factory**

In `mobile/lib/features/terminal/ssh_transport.dart`, add import:

```dart
import 'socks5_connector.dart';
```

Update constructor:

```dart
SshTransportFactory({
  SshSocketConnector? connectSocket,
  Socks5Connector? socks5Connector,
})  : _connectSocket = connectSocket ?? SSHSocket.connect,
      _socks5Connector = socks5Connector ?? Socks5Connector();

final Socks5Connector _socks5Connector;
```

Add branch before the unsupported error:

```dart
if (config.proxyType == 'proxyServer') {
  final proxy = config.proxy;
  if (proxy == null) {
    throw const SshTransportException('SOCKS5 proxy connection failed');
  }
  if (proxy.type != 'socks5') {
    throw SshTransportException('Unsupported mobile proxy type: ${proxy.type}');
  }
  final socket = await _socks5Connector.connect(
    proxyHost: proxy.host,
    proxyPort: proxy.port,
    targetHost: config.host,
    targetPort: config.port,
    username: proxy.username,
    password: proxy.password,
  );
  return SshTransportHandle(socket: socket, intermediateClients: const []);
}
```

- [ ] **Step 5: Run SOCKS5 tests and commit**

Run:

```bash
cd mobile
dart format lib/features/terminal/socks5_connector.dart lib/features/terminal/ssh_transport.dart test/features/terminal/socks5_connector_test.dart test/features/terminal/ssh_transport_test.dart
flutter test test/features/terminal
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/features/terminal/socks5_connector.dart mobile/lib/features/terminal/ssh_transport.dart mobile/test/features/terminal/socks5_connector_test.dart mobile/test/features/terminal/ssh_transport_test.dart
git commit -m "feat: support mobile socks5 ssh transport"
```

## Task 5: Jump Host Transport

**Files:**
- Modify: `mobile/lib/features/terminal/ssh_transport.dart`
- Modify: `mobile/test/features/terminal/ssh_transport_test.dart`

- [ ] **Step 1: Add jump-host fake tests**

Append to `mobile/test/features/terminal/ssh_transport_test.dart`:

```dart
test('fails when jumpHosts proxyType has empty chain', () async {
  final factory = SshTransportFactory(
    connectSocket: (host, port) async => FakeSocket('unused'),
  );
  final jumpConfig = SshConnectionConfig(
    hostId: 'h1',
    name: 'prod',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret',
    privateKey: '',
    passphrase: '',
    proxyType: 'jumpHosts',
    proxy: null,
    jumpHosts: const [],
  );

  expect(
    () => factory.open(jumpConfig),
    throwsA(isA<SshTransportException>().having(
      (error) => error.message,
      'message',
      'Jump host connection failed: empty chain',
    )),
  );
});
```

Add a second test after a fake client factory is introduced in implementation:

```dart
test('opens jump host chain and keeps intermediate clients', () async {
  final opened = <String>[];
  final closed = <String>[];
  final factory = SshTransportFactory(
    connectSocket: (host, port) async {
      opened.add('tcp:$host:$port');
      return FakeSocket(host);
    },
    createClient: (socket, auth) => FakeSshClient(
      auth.host,
      closed,
      forwardSocket: FakeSocket('forward:${auth.host}'),
    ),
  );
  final jumpConfig = SshConnectionConfig(
    hostId: 'h1',
    name: 'prod',
    host: '10.0.0.2',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret',
    privateKey: '',
    passphrase: '',
    proxyType: 'jumpHosts',
    proxy: null,
    jumpHosts: const [
      SshJumpHostConfig(
        hostId: 'j1',
        name: 'jump',
        host: '203.0.113.10',
        port: 22,
        username: 'root',
        authType: 'password',
        password: 'jump-secret',
        privateKey: '',
        passphrase: '',
      ),
    ],
  );

  final handle = await factory.open(jumpConfig);

  expect(opened, ['tcp:203.0.113.10:22']);
  expect(handle.socket, isA<FakeSocket>());
  await handle.close();
  expect(closed, ['203.0.113.10']);
});
```

- [ ] **Step 2: Refactor `ssh_transport.dart` for injectable client creation**

In `mobile/lib/features/terminal/ssh_transport.dart`, add:

```dart
abstract class SshClientHandle {
  Future<void> get authenticated;
  Future<SSHSocket> forwardLocal(String host, int port);
  void close();
}

typedef SshClientCreator = SshClientHandle Function(
  SSHSocket socket,
  SshAuthConfig auth,
);

class DartSshClientHandle implements SshClientHandle {
  DartSshClientHandle(this.client);
  final SSHClient client;

  @override
  Future<void> get authenticated => client.authenticated;

  @override
  Future<SSHSocket> forwardLocal(String host, int port) {
    return client.forwardLocal(host, port);
  }

  @override
  void close() {
    client.close();
  }
}

SshClientHandle createDartSshClient(SSHSocket socket, SshAuthConfig auth) {
  final identities = auth.authType == 'privateKey'
      ? SSHKeyPair.fromPem(auth.privateKey, auth.privateKeyPassphrase)
      : null;
  final client = SSHClient(
    socket,
    username: auth.username,
    onPasswordRequest: auth.authType == 'password' ? () => auth.password : null,
    identities: identities,
  );
  return DartSshClientHandle(client);
}
```

Update `SshTransportHandle` to store `List<SshClientHandle>` instead of `List<SSHClient>`.

Update `SshTransportFactory` constructor:

```dart
SshTransportFactory({
  SshSocketConnector? connectSocket,
  Socks5Connector? socks5Connector,
  SshClientCreator? createClient,
})  : _connectSocket = connectSocket ?? SSHSocket.connect,
      _socks5Connector = socks5Connector ?? Socks5Connector(),
      _createClient = createClient ?? createDartSshClient;

final SshClientCreator _createClient;
```

- [ ] **Step 3: Implement jump-host branch**

In `SshTransportFactory.open`, add before the unsupported error:

```dart
if (config.proxyType == 'jumpHosts') {
  if (config.jumpHosts.isEmpty) {
    throw const SshTransportException('Jump host connection failed: empty chain');
  }

  final clients = <SshClientHandle>[];
  SSHSocket socket = await _connectSocket(
    config.jumpHosts.first.host,
    config.jumpHosts.first.port,
  );

  try {
    for (var i = 0; i < config.jumpHosts.length; i++) {
      final jumpHost = config.jumpHosts[i];
      final client = _createClient(socket, jumpHost);
      clients.add(client);
      try {
        await client.authenticated;
      } catch (_) {
        throw SshTransportException(
          'Jump host authentication failed: ${jumpHost.name.isEmpty ? jumpHost.host : jumpHost.name}',
        );
      }

      final nextHost = i == config.jumpHosts.length - 1
          ? config.host
          : config.jumpHosts[i + 1].host;
      final nextPort = i == config.jumpHosts.length - 1
          ? config.port
          : config.jumpHosts[i + 1].port;
      try {
        socket = await client.forwardLocal(nextHost, nextPort);
      } catch (_) {
        throw SshTransportException(
          'Jump host forwarding failed: ${jumpHost.host} -> $nextHost',
        );
      }
    }

    return SshTransportHandle(socket: socket, intermediateClients: clients);
  } catch (_) {
    for (final client in clients.reversed) {
      client.close();
    }
    await socket.close();
    rethrow;
  }
}
```

- [ ] **Step 4: Add fake client used by tests**

In `mobile/test/features/terminal/ssh_transport_test.dart`, add:

```dart
class FakeSshClient implements SshClientHandle {
  FakeSshClient(this.label, this.closed, {required this.forwardSocket});

  final String label;
  final List<String> closed;
  final SSHSocket forwardSocket;

  @override
  Future<void> get authenticated async {}

  @override
  Future<SSHSocket> forwardLocal(String host, int port) async => forwardSocket;

  @override
  void close() {
    closed.add(label);
  }
}
```

- [ ] **Step 5: Run jump-host tests and commit**

Run:

```bash
cd mobile
dart format lib/features/terminal/ssh_transport.dart test/features/terminal/ssh_transport_test.dart
flutter test test/features/terminal
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/features/terminal/ssh_transport.dart mobile/test/features/terminal/ssh_transport_test.dart
git commit -m "feat: support mobile ssh jump hosts"
```

## Task 6: Terminal Error Output and Final Verification

**Files:**
- Modify: `mobile/lib/features/terminal/ssh_terminal_controller.dart`
- Test: existing terminal tests plus server payload test

- [ ] **Step 1: Preserve readable transport errors in terminal output**

In `mobile/lib/features/terminal/ssh_terminal_controller.dart`, wrap the transport and SSH client creation section in `connect()`:

```dart
try {
  final transport = await _transportFactory.open(config);
  _transport = transport;
  final identities = config.authType == 'privateKey'
      ? SSHKeyPair.fromPem(config.privateKey, config.privateKeyPassphrase)
      : null;
  _client = SSHClient(
    transport.socket,
    username: config.username,
    onPasswordRequest: config.authType == 'password' ? () => config.password : null,
    identities: identities,
  );
} on SshTransportException catch (error) {
  terminal.write('[Error] ${error.message}\r\n');
  rethrow;
} catch (error) {
  terminal.write('[Error] $error\r\n');
  rethrow;
}
```

Keep the existing shell/session setup after this block.

- [ ] **Step 2: Run focused verification**

Run:

```bash
node server/test/test-mobile-ssh-payload.js
cd mobile
flutter test test/features/terminal
```

Expected:

```text
test-mobile-ssh-payload passed
All tests passed!
```

- [ ] **Step 3: Run broader mobile verification**

Run:

```bash
cd mobile
flutter test
```

Expected: PASS. If unrelated pre-existing tests fail, capture exact failing test names and output in the task review before proceeding.

- [ ] **Step 4: Commit final controller error handling**

Commit:

```bash
git add mobile/lib/features/terminal/ssh_terminal_controller.dart
git commit -m "fix: show mobile ssh transport errors"
```

## Self-Review

- Spec coverage: Server encrypted payload topology, mobile config parsing, direct behavior preservation, SOCKS5 support, jump-host support, unsupported HTTP error, lifecycle cleanup, and tests are all mapped to tasks above.
- Scope: HTTP CONNECT implementation is excluded from this plan and represented as an explicit unsupported proxy error, matching the accepted design's staged support.
- Type consistency: `SshAuthConfig`, `SshProxyConfig`, `SshJumpHostConfig`, `SshTransportHandle`, `SshTransportFactory`, `SshClientHandle`, `SshTransportException`, and `Socks5Connector` are introduced before later tasks reference them.
