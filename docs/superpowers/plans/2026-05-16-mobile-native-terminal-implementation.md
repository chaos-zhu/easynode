# Mobile Native Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first EasyNode Flutter mobile app with login, server list, and native SSH terminal connection.

**Architecture:** Reuse existing EasyNode login and host-list APIs, add only `POST /api/v1/mobile/ssh-connection` for encrypted SSH credentials, and keep native SSH entirely inside the Flutter app. Mobile secrets use platform secure storage, ordinary preferences store only low-sensitivity values, and HTTP users receive an explicit risk warning before login.

**Tech Stack:** Flutter/Dart, `dio`, `cookie_jar`, `dio_cookie_manager`, `flutter_secure_storage`, `shared_preferences`, `pointycastle`, `basic_utils`, `dartssh2`, `xterm`, Node/Koa, Node `crypto`.

---

## File Structure Map

Server files:

- Create `server/app/utils/mobile-crypto.js`: AES-256-GCM response envelope helpers and temporary key validation.
- Create `server/app/controller/mobile.js`: mobile-only SSH credential controller.
- Modify `server/app/router/routes.js`: register `POST /mobile/ssh-connection`.
- Create `server/test/test-mobile-crypto.js`: pure crypto helper tests.
- Create `server/test/test-mobile-ssh-payload.js`: SSH payload shaping tests.
- Modify `server/package.json`: add `test:mobile` script.

Flutter core files:

- Replace `mobile/lib/main.dart`: app bootstrap.
- Create `mobile/lib/app.dart`: Material app, routes, and top-level controllers.
- Create `mobile/lib/core/utils/validators.dart`: server URL normalization and HTTP risk detection.
- Create `mobile/lib/core/utils/jwt_expiry.dart`: Web-compatible login-expiry conversion.
- Create `mobile/lib/core/storage/device_id.dart`: generate and persist a per-install UUID v4 device id.
- Create `mobile/lib/core/crypto/aes_gcm_crypto.dart`: AES-GCM decrypt helper for mobile credential responses.
- Create `mobile/lib/core/crypto/rsa_crypto.dart`: RSA public-key encryption compatible with EasyNode login.
- Create `mobile/lib/core/storage/app_storage.dart`: ordinary preference storage.
- Create `mobile/lib/core/storage/secure_storage.dart`: secure storage wrapper.
- Create `mobile/lib/core/api/cookie_store.dart`: session cookie persistence.
- Create `mobile/lib/core/api/api_client.dart`: EasyNode HTTP client.
- Create `mobile/lib/core/api/api_result.dart`: typed API error/result model.

Flutter feature files:

- Create `mobile/lib/features/auth/auth_session.dart`: token, device id, session state.
- Create `mobile/lib/features/auth/login_controller.dart`: login orchestration.
- Create `mobile/lib/features/auth/login_page.dart`: login UI.
- Create `mobile/lib/features/servers/server_model.dart`: host-list model.
- Create `mobile/lib/features/servers/server_repository.dart`: host-list and SSH credential requests.
- Create `mobile/lib/features/servers/server_list_page.dart`: mobile server list UI.
- Create `mobile/lib/features/terminal/ssh_connection_config.dart`: decrypted SSH config model.
- Create `mobile/lib/features/terminal/ssh_terminal_controller.dart`: `dartssh2` to xterm bridge.
- Create `mobile/lib/features/terminal/terminal_page.dart`: terminal screen.
- Create `mobile/lib/features/terminal/terminal_toolbar.dart`: mobile terminal shortcut controls.

Flutter test files:

- Create `mobile/test/core/utils/validators_test.dart`.
- Create `mobile/test/core/utils/jwt_expiry_test.dart`.
- Create `mobile/test/core/storage/device_id_test.dart`.
- Create `mobile/test/core/crypto/aes_gcm_crypto_test.dart`.
- Create `mobile/test/features/auth/login_controller_test.dart`.
- Create `mobile/test/features/servers/server_model_test.dart`.
- Create `mobile/test/features/servers/server_repository_test.dart`.
- Create `mobile/test/features/auth/login_page_test.dart`.
- Create `mobile/test/features/servers/server_list_page_test.dart`.

Platform files:

- Modify `mobile/pubspec.yaml`: add mobile dependencies.
- Modify `mobile/android/app/src/main/AndroidManifest.xml`: add `INTERNET` and cleartext policy.
- Create `mobile/android/app/src/main/res/xml/network_security_config.xml`: allow user-provided HTTP servers.
- Modify `mobile/ios/Runner/Info.plist`: add ATS exception for user-provided HTTP.

## Task 1: Server AES-GCM Mobile Envelope

**Files:**
- Create: `server/app/utils/mobile-crypto.js`
- Create: `server/test/test-mobile-crypto.js`
- Modify: `server/package.json`

- [ ] **Step 1: Write failing crypto tests**

Create `server/test/test-mobile-crypto.js`:

```js
const assert = require('assert')
const { encryptJsonForMobile, decryptMobileJsonForTest, assertTempKey } = require('../app/utils/mobile-crypto')

function testRejectsShortKey() {
  assert.throws(() => assertTempKey(Buffer.alloc(16)), /temporary key must be 32 bytes/)
}

function testEncryptsAndDecryptsJson() {
  const key = Buffer.from('0123456789abcdef0123456789abcdef')
  const payload = { host: '127.0.0.1', password: 'secret' }
  const envelope = encryptJsonForMobile(payload, key)

  assert.strictEqual(envelope.alg, 'AES-256-GCM')
  assert.ok(envelope.iv)
  assert.ok(envelope.tag)
  assert.ok(envelope.ciphertext)
  assert.ok(!JSON.stringify(envelope).includes('secret'))

  const decoded = decryptMobileJsonForTest(envelope, key)
  assert.deepStrictEqual(decoded, payload)
}

testRejectsShortKey()
testEncryptsAndDecryptsJson()
console.log('test-mobile-crypto passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node server/test/test-mobile-crypto.js`

Expected: FAIL with `Cannot find module '../app/utils/mobile-crypto'`.

- [ ] **Step 3: Implement the crypto helper**

Create `server/app/utils/mobile-crypto.js`:

```js
const crypto = require('crypto')

function assertTempKey(key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new Error('temporary key must be 32 bytes')
  }
}

function encryptJsonForMobile(payload, key) {
  assertTempKey(key)
  const iv = crypto.randomBytes(12)
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv)
  const plaintext = Buffer.from(JSON.stringify(payload), 'utf8')
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()])
  const tag = cipher.getAuthTag()

  return {
    alg: 'AES-256-GCM',
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
    ciphertext: ciphertext.toString('base64')
  }
}

function decryptMobileJsonForTest(envelope, key) {
  assertTempKey(key)
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(envelope.iv, 'base64')
  )
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'))
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
    decipher.final()
  ])
  return JSON.parse(plaintext.toString('utf8'))
}

module.exports = {
  assertTempKey,
  encryptJsonForMobile,
  decryptMobileJsonForTest
}
```

- [ ] **Step 4: Add the server test script**

Modify `server/package.json` scripts:

```json
"test:mobile": "node test/test-mobile-crypto.js && node test/test-mobile-ssh-payload.js"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node server/test/test-mobile-crypto.js`

Expected: PASS and prints `test-mobile-crypto passed`.

- [ ] **Step 6: Commit**

Run:

```bash
git add server/app/utils/mobile-crypto.js server/test/test-mobile-crypto.js server/package.json
git commit -m "test: add mobile crypto envelope"
```

## Task 2: Server SSH Payload Shaping

**Files:**
- Create: `server/app/controller/mobile.js`
- Create: `server/test/test-mobile-ssh-payload.js`

- [ ] **Step 1: Write failing payload tests**

Create `server/test/test-mobile-ssh-payload.js`:

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
    passphrase: ''
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
}

function testRejectsUnsupportedAuth() {
  assert.throws(() => toMobileSshPayload('h3', 'unsupported', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'keyboard'
  }), /unsupported mobile ssh auth type/)
}

testPasswordPayload()
testPrivateKeyPayload()
testRejectsUnsupportedAuth()
console.log('test-mobile-ssh-payload passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node server/test/test-mobile-ssh-payload.js`

Expected: FAIL because `server/app/controller/mobile.js` does not exist.

- [ ] **Step 3: Implement payload helper and controller skeleton**

Create `server/app/controller/mobile.js`:

```js
const { RSADecryptAsync } = require('../utils/encrypt')
const { getConnectionOptions } = require('../socket/terminal')
const { encryptJsonForMobile } = require('../utils/mobile-crypto')

function toMobileSshPayload(hostId, name, authInfo) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported mobile ssh auth type: ${ authType || 'empty' }`)
  }

  const numericPort = Number(port)
  return {
    hostId,
    name,
    host,
    port: Number.isFinite(numericPort) && numericPort > 0 ? numericPort : 22,
    username,
    authType,
    password: authType === 'password' ? authInfo.password || '' : '',
    privateKey: authType === 'privateKey' ? authInfo.privateKey || '' : '',
    passphrase: authType === 'privateKey' ? authInfo.passphrase || '' : ''
  }
}

async function getMobileSshConnection({ request, res }) {
  try {
    const { hostId, encryptedKey } = request.body || {}
    if (!hostId || !encryptedKey) {
      return res.fail({ msg: 'missing params' })
    }

    const tempKeyText = await RSADecryptAsync(encryptedKey)
    const tempKey = Buffer.from(tempKeyText, 'base64')
    const { authInfo, name } = await getConnectionOptions(hostId)
    const payload = toMobileSshPayload(hostId, name, authInfo)
    const data = encryptJsonForMobile(payload, tempKey)

    return res.success({ data, msg: 'success' })
  } catch (error) {
    // Detail goes to the server log; the wire response is intentionally generic.
    logger.error('getMobileSshConnection error:', error.message)
    return res.fail({ msg: 'mobile ssh connection failed' })
  }
}

module.exports = {
  getMobileSshConnection,
  toMobileSshPayload
}
```

> **Logger note:** the EasyNode runtime exposes `global.logger`, so this controller calls `logger.*` directly without an explicit `require`.

- [ ] **Step 4: Run test to verify it passes**

Run: `node server/test/test-mobile-ssh-payload.js`

Expected: PASS and prints `test-mobile-ssh-payload passed`.

- [ ] **Step 5: Commit**

Run:

```bash
git add server/app/controller/mobile.js server/test/test-mobile-ssh-payload.js
git commit -m "test: add mobile ssh payload shaping"
```

## Task 3: Register Mobile SSH API

**Files:**
- Modify: `server/app/router/routes.js`

- [ ] **Step 1: Add route import**

Modify the top of `server/app/router/routes.js`:

```js
const { getMobileSshConnection } = require('../controller/mobile')
```

- [ ] **Step 2: Add route group**

Add near the terminal routes:

```js
const mobile = [
  {
    method: 'post',
    path: '/mobile/ssh-connection',
    controller: getMobileSshConnection
  }
]
```

- [ ] **Step 3: Include route group in export**

Modify the final `module.exports = [].concat(...)` call to include `mobile`:

```js
module.exports = [].concat(
  ssh,
  host,
  user,
  notify,
  group,
  scripts,
  scriptGroup,
  onekey,
  log,
  aiConfig,
  proxy,
  terminalConfig,
  serverListConfig,
  terminal,
  mobile
)
```

- [ ] **Step 4: Run server mobile tests**

Run: `yarn workspace server run test:mobile`

Expected: both mobile tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add server/app/router/routes.js
git commit -m "feat: register mobile ssh connection API"
```

## Task 4: Flutter Dependencies and Platform Network Policy

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/android/app/src/main/res/xml/network_security_config.xml`
- Modify: `mobile/ios/Runner/Info.plist`

- [ ] **Step 1: Add dependencies**

Run from `mobile`:

```bash
flutter pub add dio cookie_jar dio_cookie_manager flutter_secure_storage shared_preferences pointycastle basic_utils dartssh2 xterm
```

Expected: `mobile/pubspec.yaml` and `mobile/pubspec.lock` update.

- [ ] **Step 2: Add Android network permission and config reference**

Modify `mobile/android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="mobile"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true"
        android:networkSecurityConfig="@xml/network_security_config">
```

- [ ] **Step 3: Add Android network security config**

Create `mobile/android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
```

- [ ] **Step 4: Add iOS ATS exception**

Inside the root `<dict>` in `mobile/ios/Runner/Info.plist`, add:

```xml
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
```

- [ ] **Step 5: Run dependency verification**

Run from `mobile`: `flutter pub get`

Expected: exits 0.

- [ ] **Step 6: Commit**

Run:

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/android/app/src/main/AndroidManifest.xml mobile/android/app/src/main/res/xml/network_security_config.xml mobile/ios/Runner/Info.plist
git commit -m "chore: add mobile app network dependencies"
```

## Task 5: Flutter Core Utilities

**Files:**
- Create: `mobile/lib/core/utils/validators.dart`
- Create: `mobile/lib/core/utils/jwt_expiry.dart`
- Create: `mobile/lib/core/storage/device_id.dart`
- Create: `mobile/test/core/utils/validators_test.dart`
- Create: `mobile/test/core/utils/jwt_expiry_test.dart`
- Create: `mobile/test/core/storage/device_id_test.dart`

> **Note on `jwtExpiresFor` values:** the strings returned by this helper are passed directly to the existing EasyNode `/api/v1/login` endpoint as the `jwtExpires` field. The server forwards `jwtExpires` to `jsonwebtoken`'s `sign({ expiresIn })`, which accepts the string formats produced here (`1h`, `<seconds>s`, `3d`, `7d`). Verify against `server/app/controller/user.js` (`beforeLoginHandler`, around line 97) before changing the values.

- [ ] **Step 1: Write utility tests**

Create `mobile/test/core/utils/validators_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/validators.dart';

void main() {
  test('normalizes server address by trimming and removing trailing slash', () {
    expect(normalizeServerAddress(' http://127.0.0.1:8082/ '), 'http://127.0.0.1:8082');
  });

  test('detects http risk', () {
    expect(isHttpAddress('http://127.0.0.1:8082'), isTrue);
    expect(isHttpAddress('https://example.com'), isFalse);
  });

  test('rejects unsupported scheme', () {
    expect(() => normalizeServerAddress('ftp://example.com'), throwsA(isA<FormatException>()));
  });
}
```

Create `mobile/test/core/utils/jwt_expiry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/jwt_expiry.dart';

void main() {
  test('maps temporary expiry to one hour', () {
    expect(jwtExpiresFor(LoginExpiry.temporary), '1h');
  });

  test('maps three days and seven days', () {
    expect(jwtExpiresFor(LoginExpiry.threeDays), '3d');
    expect(jwtExpiresFor(LoginExpiry.sevenDays), '7d');
  });
}
```

Create `mobile/test/core/storage/device_id_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/device_id.dart';

class _FakeStore implements DeviceIdStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

void main() {
  test('generates and persists a uuid v4 device id on first read', () async {
    final store = _FakeStore();
    final id = await loadOrCreateDeviceId(store);
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    final again = await loadOrCreateDeviceId(store);
    expect(again, id);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `mobile`: `flutter test test/core`

Expected: FAIL because utility files do not exist.

- [ ] **Step 3: Implement utilities**

Create `mobile/lib/core/utils/validators.dart`:

```dart
String normalizeServerAddress(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('请输入有效的服务端地址');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('服务端地址仅支持 http 或 https');
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

bool isHttpAddress(String input) {
  final uri = Uri.tryParse(input.trim());
  return uri?.scheme == 'http';
}
```

Create `mobile/lib/core/utils/jwt_expiry.dart`:

```dart
enum LoginExpiry { temporary, currentDay, threeDays, sevenDays }

String jwtExpiresFor(LoginExpiry expiry, {DateTime? now}) {
  switch (expiry) {
    case LoginExpiry.temporary:
      return '1h';
    case LoginExpiry.currentDay:
      final current = now ?? DateTime.now();
      final tomorrow = DateTime(current.year, current.month, current.day + 1);
      final seconds = tomorrow.difference(current).inSeconds;
      return '${seconds}s';
    case LoginExpiry.threeDays:
      return '3d';
    case LoginExpiry.sevenDays:
      return '7d';
  }
}

int jwtExpireAtFor(LoginExpiry expiry, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final expires = jwtExpiresFor(expiry, now: current);
  final match = RegExp(r'^(\d+)([smhd])$').firstMatch(expires);
  if (match == null) throw const FormatException('invalid jwt expiry');
  final count = int.parse(match.group(1)!);
  final unit = match.group(2)!;
  final multiplier = switch (unit) {
    's' => 1000,
    'm' => 60 * 1000,
    'h' => 60 * 60 * 1000,
    'd' => 24 * 60 * 60 * 1000,
    _ => 1000,
  };
  return current.millisecondsSinceEpoch + count * multiplier;
}
```

Create `mobile/lib/core/storage/device_id.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

abstract class DeviceIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureDeviceIdStore implements DeviceIdStore {
  SecureDeviceIdStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'mobileDeviceId';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

Future<String> loadOrCreateDeviceId(DeviceIdStore store) async {
  final existing = await store.read();
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await store.write(id);
  return id;
}
```

- [ ] **Step 4: Add missing `uuid` dependency**

Run from `mobile`: `flutter pub add uuid`

Expected: `uuid` is added because `loadOrCreateDeviceId` uses it.

- [ ] **Step 5: Run tests to verify they pass**

Run from `mobile`: `flutter test test/core`

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add mobile/lib/core mobile/test/core mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "test: add mobile core utilities"
```

## Task 6: AES-GCM and RSA Crypto in Flutter

**Files:**
- Create: `mobile/lib/core/crypto/aes_gcm_crypto.dart`
- Create: `mobile/lib/core/crypto/rsa_crypto.dart`
- Create: `mobile/test/core/crypto/aes_gcm_crypto_test.dart`

- [ ] **Step 1: Write AES-GCM response decrypt test**

Create `mobile/test/core/crypto/aes_gcm_crypto_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:mobile/core/crypto/aes_gcm_crypto.dart';

void main() {
  test('decrypts AES-GCM envelope', () {
    final key = utf8.encode('0123456789abcdef0123456789abcdef');
    final iv = List<int>.generate(12, (i) => i);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, Uint8List.fromList(iv), Uint8List(0)));
    final plain = utf8.encode('{"host":"127.0.0.1"}');
    final encrypted = cipher.process(Uint8List.fromList(plain));
    final tag = encrypted.sublist(encrypted.length - 16);
    final ciphertext = encrypted.sublist(0, encrypted.length - 16);

    final decoded = decryptAesGcmJson(
      key: Uint8List.fromList(key),
      ivBase64: base64Encode(iv),
      tagBase64: base64Encode(tag),
      ciphertextBase64: base64Encode(ciphertext),
    );

    expect(decoded['host'], '127.0.0.1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `mobile`: `flutter test test/core/crypto/aes_gcm_crypto_test.dart`

Expected: FAIL because `aes_gcm_crypto.dart` does not exist.

- [ ] **Step 3: Implement AES-GCM helper**

Create `mobile/lib/core/crypto/aes_gcm_crypto.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

Map<String, dynamic> decryptAesGcmJson({
  required Uint8List key,
  required String ivBase64,
  required String tagBase64,
  required String ciphertextBase64,
}) {
  if (key.length != 32) {
    throw ArgumentError('temporary key must be 32 bytes');
  }
  final iv = base64Decode(ivBase64);
  final tag = base64Decode(tagBase64);
  final ciphertext = base64Decode(ciphertextBase64);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, Uint8List.fromList(iv), Uint8List(0)));
  final combined = Uint8List.fromList([...ciphertext, ...tag]);
  final plaintext = cipher.process(combined);
  return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
}
```

- [ ] **Step 4: Implement RSA helper API**

Create `mobile/lib/core/crypto/rsa_crypto.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class RsaCrypto {
  String encryptPassword(String publicKeyPem, String plaintext) {
    final key = _parsePublicKey(publicKeyPem);
    final engine = PKCS1Encoding(RSAEngine())..init(true, PublicKeyParameter<RSAPublicKey>(key));
    return base64Encode(engine.process(Uint8List.fromList(utf8.encode(plaintext))));
  }

  String encryptTemporaryKey(String publicKeyPem, Uint8List keyBytes) {
    // Server side decrypts RSA to a utf8 string via `rsakey.decrypt(ct, 'utf8')`
    // and then does `Buffer.from(text, 'base64')`. We therefore base64-encode the
    // raw key bytes before RSA-encrypting, so the round trip restores the 32B key.
    final key = _parsePublicKey(publicKeyPem);
    final engine = PKCS1Encoding(RSAEngine())..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final base64Text = base64Encode(keyBytes);
    final encrypted = engine.process(Uint8List.fromList(utf8.encode(base64Text)));
    return base64Encode(encrypted);
  }

  RSAPublicKey _parsePublicKey(String publicKeyPem) {
    return CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
  }
}
```

- [ ] **Step 5: Run AES-GCM test to verify it passes**

Run from `mobile`: `flutter test test/core/crypto/aes_gcm_crypto_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add mobile/lib/core/crypto mobile/test/core/crypto mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "test: add mobile response crypto"
```

## Task 7: Storage and Cookie Persistence

**Files:**
- Create: `mobile/lib/core/storage/app_storage.dart`
- Create: `mobile/lib/core/storage/secure_storage.dart`
- Create: `mobile/lib/core/api/cookie_store.dart`

- [ ] **Step 1: Implement ordinary storage wrapper**

Create `mobile/lib/core/storage/app_storage.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  AppStorage(this._prefs);
  final SharedPreferences _prefs;

  String get serverAddress => _prefs.getString('serverAddress') ?? '';
  Future<void> setServerAddress(String value) => _prefs.setString('serverAddress', value);

  String get username => _prefs.getString('username') ?? '';
  Future<void> setUsername(String value) => _prefs.setString('username', value);

  bool get savePassword => _prefs.getBool('savePassword') ?? false;
  Future<void> setSavePassword(bool value) => _prefs.setBool('savePassword', value);
}
```

- [ ] **Step 2: Implement secure storage wrapper**

Create `mobile/lib/core/storage/secure_storage.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureAppStorage {
  SecureAppStorage(this._storage);
  final FlutterSecureStorage _storage;

  Future<String?> readPassword(String serverAddress, String username) {
    return _storage.read(key: 'password:$serverAddress:$username');
  }

  Future<void> writePassword(String serverAddress, String username, String password) {
    return _storage.write(key: 'password:$serverAddress:$username', value: password);
  }

  Future<void> deletePassword(String serverAddress, String username) {
    return _storage.delete(key: 'password:$serverAddress:$username');
  }

  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> writeToken(String token) => _storage.write(key: 'token', value: token);
  Future<void> deleteToken() => _storage.delete(key: 'token');

  Future<String?> readSessionCookie() => _storage.read(key: 'sessionCookie');
  Future<void> writeSessionCookie(String value) => _storage.write(key: 'sessionCookie', value: value);
  Future<void> deleteSessionCookie() => _storage.delete(key: 'sessionCookie');
}
```

- [ ] **Step 3: Implement cookie persistence helper**

Create `mobile/lib/core/api/cookie_store.dart`:

```dart
import '../storage/secure_storage.dart';

class SessionCookieStore {
  SessionCookieStore(this._storage);
  final SecureAppStorage _storage;

  Future<void> saveFromSetCookieHeaders(List<String> headers) async {
    for (final header in headers) {
      final firstPart = header.split(';').first.trim();
      if (firstPart.startsWith('session=')) {
        await _storage.writeSessionCookie(firstPart);
        return;
      }
    }
  }

  Future<String?> readCookieHeader() => _storage.readSessionCookie();
}
```

- [ ] **Step 4: Run analyzer**

Run from `mobile`: `flutter analyze`

Expected: no errors from the new storage files.

- [ ] **Step 5: Commit**

Run:

```bash
git add mobile/lib/core/storage mobile/lib/core/api/cookie_store.dart
git commit -m "feat: add mobile credential storage"
```

## Task 8: API Client and Login Controller

**Files:**
- Create: `mobile/lib/core/api/api_client.dart`
- Create: `mobile/lib/core/api/api_result.dart`
- Create: `mobile/lib/features/auth/auth_session.dart`
- Create: `mobile/lib/features/auth/login_controller.dart`
- Create: `mobile/test/features/auth/login_controller_test.dart`

- [ ] **Step 1: Write login controller test with fake API**

Create `mobile/test/features/auth/login_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/login_controller.dart';

void main() {
  test('blocks http login until user confirms risk', () async {
    final controller = LoginController.fake();
    final result = await controller.login(
      serverAddress: 'http://127.0.0.1:8082',
      username: 'root',
      password: 'secret',
      mfa2Token: '',
      httpRiskAccepted: false,
      savePassword: false,
    );

    expect(result.requiresHttpRiskConfirmation, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `mobile`: `flutter test test/features/auth/login_controller_test.dart`

Expected: FAIL because `login_controller.dart` does not exist.

- [ ] **Step 3: Implement API result model**

Create `mobile/lib/core/api/api_result.dart`:

```dart
class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
```

- [ ] **Step 4: Implement auth session**

Create `mobile/lib/features/auth/auth_session.dart`:

```dart
class AuthSession {
  const AuthSession({
    required this.token,
    required this.deviceId,
  });

  final String token;
  final String deviceId;
}
```

- [ ] **Step 5: Implement minimal login controller**

Create `mobile/lib/features/auth/login_controller.dart`:

```dart
import '../../core/utils/validators.dart';

class LoginResult {
  const LoginResult({
    this.success = false,
    this.requiresHttpRiskConfirmation = false,
    this.message = '',
  });

  final bool success;
  final bool requiresHttpRiskConfirmation;
  final String message;
}

class LoginController {
  LoginController();
  factory LoginController.fake() => LoginController();

  Future<LoginResult> login({
    required String serverAddress,
    required String username,
    required String password,
    required String mfa2Token,
    required bool httpRiskAccepted,
    required bool savePassword,
  }) async {
    final normalized = normalizeServerAddress(serverAddress);
    if (isHttpAddress(normalized) && !httpRiskAccepted) {
      return const LoginResult(requiresHttpRiskConfirmation: true);
    }
    if (username.trim().isEmpty) {
      return const LoginResult(message: '请输入用户名');
    }
    if (password.isEmpty) {
      return const LoginResult(message: '请输入密码');
    }
    return const LoginResult(success: true);
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run from `mobile`: `flutter test test/features/auth/login_controller_test.dart`

Expected: PASS.

- [ ] **Step 7: Implement HTTP API client shell**

Create `mobile/lib/core/api/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'api_result.dart';
import 'cookie_store.dart';

class ApiClient {
  ApiClient({
    required String serverAddress,
    required SessionCookieStore cookieStore,
    String? token,
  })  : _cookieStore = cookieStore,
        _dio = Dio(BaseOptions(baseUrl: '$serverAddress/api/v1', connectTimeout: const Duration(seconds: 30))) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (token != null && token.isNotEmpty) options.headers['token'] = token;
        final cookie = await _cookieStore.readCookieHeader();
        if (cookie != null && cookie.isNotEmpty) options.headers['Cookie'] = cookie;
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final cookies = response.headers.map['set-cookie'];
        if (cookies != null) await _cookieStore.saveFromSetCookieHeaders(cookies);
        handler.next(response);
      },
    ));
  }

  final Dio _dio;
  final SessionCookieStore _cookieStore;

  Future<String> getPublicKey() async {
    final response = await _dio.get('/get-pub-pem');
    return response.data['data'] as String;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _dio.get(path);
      return response.data as Map<String, dynamic>;
    } on DioException catch (error) {
      throw ApiFailure(error.response?.data?['msg']?.toString() ?? error.message ?? '网络错误',
          statusCode: error.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (error) {
      throw ApiFailure(error.response?.data?['msg']?.toString() ?? error.message ?? '网络错误',
          statusCode: error.response?.statusCode);
    }
  }
}
```

- [ ] **Step 8: Commit**

Run:

```bash
git add mobile/lib/core/api mobile/lib/features/auth mobile/test/features/auth
git commit -m "test: add mobile login controller"
```

## Task 9: Server Model and Repository

**Files:**
- Create: `mobile/lib/features/servers/server_model.dart`
- Create: `mobile/lib/features/servers/server_repository.dart`
- Create: `mobile/test/features/servers/server_model_test.dart`
- Create: `mobile/test/features/servers/server_repository_test.dart`
- Create: `mobile/lib/features/terminal/ssh_connection_config.dart`

- [ ] **Step 1: Write server model test**

Create `mobile/test/features/servers/server_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_model.dart';

void main() {
  test('parses host-list item', () {
    final server = ServerModel.fromJson({
      'id': 'h1',
      'name': 'prod',
      'host': '10.0.0.2',
      'port': 22,
      'username': 'root',
      'authType': 'password',
      'isConfig': true,
    });

    expect(server.id, 'h1');
    expect(server.connectionLabel, 'root@10.0.0.2:22');
    expect(server.canConnect, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `mobile`: `flutter test test/features/servers/server_model_test.dart`

Expected: FAIL because `server_model.dart` does not exist.

- [ ] **Step 3: Implement server model**

Create `mobile/lib/features/servers/server_model.dart`:

```dart
class ServerModel {
  const ServerModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.isConfig,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final bool isConfig;

  String get connectionLabel => '$username@$host:$port';
  bool get canConnect => isConfig && id.isNotEmpty;

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    return ServerModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: int.tryParse((json['port'] ?? 22).toString()) ?? 22,
      username: (json['username'] ?? '').toString(),
      authType: (json['authType'] ?? '').toString(),
      isConfig: json['isConfig'] == true,
    );
  }
}
```

- [ ] **Step 4: Implement SSH config model**

Create `mobile/lib/features/terminal/ssh_connection_config.dart`:

```dart
class SshConnectionConfig {
  const SshConnectionConfig({
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

  factory SshConnectionConfig.fromJson(Map<String, dynamic> json) {
    return SshConnectionConfig(
      hostId: json['hostId'].toString(),
      name: json['name'].toString(),
      host: json['host'].toString(),
      port: int.tryParse(json['port'].toString()) ?? 22,
      username: json['username'].toString(),
      authType: json['authType'].toString(),
      password: (json['password'] ?? '').toString(),
      privateKey: (json['privateKey'] ?? '').toString(),
      passphrase: (json['passphrase'] ?? '').toString(),
    );
  }
}
```

- [ ] **Step 5: Implement repository shell**

Create `mobile/lib/features/servers/server_repository.dart`:

```dart
import 'dart:typed_data';
import '../../core/api/api_client.dart';
import '../../core/crypto/aes_gcm_crypto.dart';
import '../terminal/ssh_connection_config.dart';
import 'server_model.dart';

class ServerRepository {
  ServerRepository(this._apiClient);
  final ApiClient _apiClient;

  Future<List<ServerModel>> fetchServers() async {
    final response = await _apiClient.getJson('/host-list');
    final data = response['data'] as List<dynamic>;
    return data.map((item) => ServerModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  SshConnectionConfig decodeEncryptedConnection(Map<String, dynamic> envelope, Uint8List tempKey) {
    final data = decryptAesGcmJson(
      key: tempKey,
      ivBase64: envelope['iv'].toString(),
      tagBase64: envelope['tag'].toString(),
      ciphertextBase64: envelope['ciphertext'].toString(),
    );
    return SshConnectionConfig.fromJson(data);
  }
}
```

- [ ] **Step 6: Run model test**

Run from `mobile`: `flutter test test/features/servers/server_model_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add mobile/lib/features/servers mobile/lib/features/terminal/ssh_connection_config.dart mobile/test/features/servers
git commit -m "test: add mobile server models"
```

## Task 10: Login Page and App Routing

**Files:**
- Replace: `mobile/lib/main.dart`
- Create: `mobile/lib/app.dart`
- Create: `mobile/lib/features/auth/login_page.dart`
- Create: `mobile/test/features/auth/login_page_test.dart`

- [ ] **Step 1: Write login page widget test**

Create `mobile/test/features/auth/login_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/login_page.dart';

void main() {
  testWidgets('renders login fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('EasyNode'), findsOneWidget);
    expect(find.byKey(const Key('serverAddressField')), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `mobile`: `flutter test test/features/auth/login_page_test.dart`

Expected: FAIL because `login_page.dart` does not exist.

- [ ] **Step 3: Implement app entry**

Replace `mobile/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const EasyNodeMobileApp());
}
```

Create `mobile/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'features/auth/login_page.dart';

class EasyNodeMobileApp extends StatelessWidget {
  const EasyNodeMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyNode',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)),
      home: const LoginPage(),
    );
  }
}
```

- [ ] **Step 4: Implement login page UI skeleton**

Create `mobile/lib/features/auth/login_page.dart`:

```dart
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            Text('EasyNode', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            const TextField(
              key: Key('serverAddressField'),
              decoration: InputDecoration(labelText: '服务端地址'),
            ),
            const SizedBox(height: 12),
            const TextField(
              key: Key('usernameField'),
              decoration: InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: 12),
            const TextField(
              key: Key('passwordField'),
              obscureText: true,
              decoration: InputDecoration(labelText: '密码'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: false,
              onChanged: (_) {},
              title: const Text('保存密码'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () {}, child: const Text('登录')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run widget test**

Run from `mobile`: `flutter test test/features/auth/login_page_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add mobile/lib/main.dart mobile/lib/app.dart mobile/lib/features/auth/login_page.dart mobile/test/features/auth/login_page_test.dart
git commit -m "test: add mobile login page"
```

## Task 11: Server List Page

**Files:**
- Create: `mobile/lib/features/servers/server_list_page.dart`
- Create: `mobile/test/features/servers/server_list_page_test.dart`

- [ ] **Step 1: Write server list widget test**

Create `mobile/test/features/servers/server_list_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_list_page.dart';
import 'package:mobile/features/servers/server_model.dart';

void main() {
  testWidgets('renders server and connect action', (tester) async {
    const servers = [
      ServerModel(
        id: 'h1',
        name: 'prod',
        host: '10.0.0.2',
        port: 22,
        username: 'root',
        authType: 'password',
        isConfig: true,
      ),
    ];

    await tester.pumpWidget(const MaterialApp(home: ServerListPage(initialServers: servers)));

    expect(find.text('prod'), findsOneWidget);
    expect(find.text('root@10.0.0.2:22'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `mobile`: `flutter test test/features/servers/server_list_page_test.dart`

Expected: FAIL because `server_list_page.dart` does not exist.

- [ ] **Step 3: Implement server list page**

Create `mobile/lib/features/servers/server_list_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'server_model.dart';

class ServerListPage extends StatelessWidget {
  const ServerListPage({
    super.key,
    this.initialServers = const [],
  });

  final List<ServerModel> initialServers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器')),
      body: initialServers.isEmpty
          ? const Center(child: Text('暂无服务器'))
          : ListView.separated(
              itemCount: initialServers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final server = initialServers[index];
                return ListTile(
                  title: Text(server.name),
                  subtitle: Text(server.connectionLabel),
                  trailing: FilledButton(
                    onPressed: server.canConnect ? () {} : null,
                    child: const Text('连接'),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: Run widget test**

Run from `mobile`: `flutter test test/features/servers/server_list_page_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add mobile/lib/features/servers/server_list_page.dart mobile/test/features/servers/server_list_page_test.dart
git commit -m "test: add mobile server list page"
```

## Task 12: Terminal Controller and Terminal Page

**Files:**
- Create: `mobile/lib/features/terminal/ssh_terminal_controller.dart`
- Create: `mobile/lib/features/terminal/terminal_page.dart`
- Create: `mobile/lib/features/terminal/terminal_toolbar.dart`

- [ ] **Step 1: Implement terminal controller interface**

Create `mobile/lib/features/terminal/ssh_terminal_controller.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'ssh_connection_config.dart';

class SshTerminalController {
  SshTerminalController({
    required this.config,
    Terminal? terminal,
  }) : terminal = terminal ?? Terminal();

  final SshConnectionConfig config;
  final Terminal terminal;
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<List<int>>? _stdoutSub;

  Future<void> connect() async {
    final socket = await SSHSocket.connect(config.host, config.port);
    // dartssh2 `SSHKeyPair.fromPem` returns `List<SSHKeyPair>` already, so we
    // assign the call result directly without wrapping it in another list.
    final identities = config.authType == 'privateKey'
        ? SSHKeyPair.fromPem(config.privateKey, config.passphrase)
        : null;
    _client = SSHClient(
      socket,
      username: config.username,
      onPasswordRequest: config.authType == 'password' ? () => config.password : null,
      identities: identities,
    );
    _session = await _client!.shell();
    _stdoutSub = _session!.stdout.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    terminal.onOutput = (data) {
      _session?.write(utf8.encode(data));
    };
  }

  void resize(int columns, int rows) {
    _session?.resizeTerminal(columns, rows);
  }

  void writeInput(String data) {
    // Toolbar shortcuts must reach the SSH session, not the local xterm buffer,
    // so they are written through the session here.
    _session?.write(utf8.encode(data));
  }

  Future<void> disconnect() async {
    await _stdoutSub?.cancel();
    _session?.close();
    _client?.close();
  }
}
```

- [ ] **Step 2: Implement terminal toolbar**

Create `mobile/lib/features/terminal/terminal_toolbar.dart`:

```dart
import 'package:flutter/material.dart';

class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.onInput,
    required this.onDisconnect,
  });

  final ValueChanged<String> onInput;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            TextButton(onPressed: () => onInput('\x1b'), child: const Text('Esc')),
            TextButton(onPressed: () => onInput('\t'), child: const Text('Tab')),
            TextButton(onPressed: () => onInput('\r'), child: const Text('Enter')),
            TextButton(onPressed: onDisconnect, child: const Text('断开')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement terminal page**

Create `mobile/lib/features/terminal/terminal_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';
import 'ssh_connection_config.dart';
import 'ssh_terminal_controller.dart';
import 'terminal_toolbar.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.config});
  final SshConnectionConfig config;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final SshTerminalController controller;

  @override
  void initState() {
    super.initState();
    controller = SshTerminalController(config: widget.config);
    controller.connect();
  }

  @override
  void dispose() {
    controller.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.config.name)),
      body: Column(
        children: [
          Expanded(child: TerminalView(controller.terminal)),
          TerminalToolbar(
            onInput: controller.writeInput,
            onDisconnect: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run analyzer**

Run from `mobile`: `flutter analyze`

Expected: no analyzer errors from terminal files.

- [ ] **Step 5: Commit**

Run:

```bash
git add mobile/lib/features/terminal
git commit -m "feat: add native ssh terminal screen"
```

## Task 13: End-to-End Wiring

**Files:**
- Modify: `mobile/lib/features/auth/login_controller.dart`
- Modify: `mobile/lib/features/auth/login_page.dart`
- Modify: `mobile/lib/features/servers/server_repository.dart`
- Modify: `mobile/lib/features/servers/server_list_page.dart`
- Modify: `mobile/lib/app.dart`

- [ ] **Step 1: Wire successful login to server list**

Modify `mobile/lib/app.dart` so the root can switch from `LoginPage` to `ServerListPage` after login. Use a small `StatefulWidget` and pass a callback instead of adding a routing framework.

- [ ] **Step 2: Wire login controller to real API**

Modify `LoginController.login` to:

1. normalize server address
2. enforce HTTP confirmation
3. load or create the persisted `deviceId` (UUID v4, secure storage)
4. fetch `/get-pub-pem`
5. RSA-encrypt password
6. post `/login` with the `deviceId` field included
7. store token, session cookie, address, username, and optional password

- [ ] **Step 3: Wire server list refresh**

Modify `ServerListPage` to accept a `ServerRepository`, load servers on `initState`, and provide pull-to-refresh.

- [ ] **Step 4: Wire connect action**

Modify `ServerRepository` to:

1. generate a 32-byte temporary key
2. RSA-encrypt it with the saved public key
3. call `POST /mobile/ssh-connection`
4. decrypt the returned AES-GCM envelope
5. return `SshConnectionConfig`

- [ ] **Step 5: Navigate to terminal**

Modify `ServerListPage` connect button to call the repository and push `TerminalPage(config: config)`.

- [ ] **Step 6: Run mobile tests**

Run from `mobile`: `flutter test`

Expected: all Flutter tests pass.

- [ ] **Step 7: Run server mobile tests**

Run: `yarn workspace server run test:mobile`

Expected: all server mobile tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add mobile/lib mobile/test
git commit -m "feat: wire mobile login server list and terminal"
```

## Task 14: Final Verification

**Files:**
- Verify changed files only.

- [ ] **Step 1: Run server tests**

Run: `yarn workspace server run test:mobile`

Expected: PASS.

- [ ] **Step 2: Run Flutter tests**

Run from `mobile`: `flutter test`

Expected: PASS.

- [ ] **Step 3: Run Flutter analyzer**

Run from `mobile`: `flutter analyze`

Expected: no errors.

- [ ] **Step 4: Build Android debug APK**

Run from `mobile`: `flutter build apk --debug`

Expected: debug APK builds.

- [ ] **Step 5: Manual smoke test**

Use a local EasyNode server with at least one password-auth host and one private-key host:

1. Launch app on Android emulator or device.
2. Enter HTTP server address and verify the warning appears.
3. Accept warning and log in.
4. Verify server address and username remain on returning to login.
5. Open server list.
6. Connect password-auth host.
7. Disconnect and return.
8. Connect private-key host.

- [ ] **Step 6: Commit final fixes**

If verification required changes, commit them:

```bash
git add mobile server
git commit -m "fix: stabilize mobile native terminal verification"
```

If no changes were required, do not create an empty commit.
