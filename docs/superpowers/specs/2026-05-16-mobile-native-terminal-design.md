# EasyNode Mobile Native Terminal Design

Date: 2026-05-16

## Goal

Build the first mobile EasyNode app with Flutter for Android and iOS. The first release focuses on login, server list, and native SSH terminal connection. Existing Web and server behavior must remain compatible.

The app may learn from `C:\Users\chaos\Desktop\flutter_server_box` only at the level of general implementation ideas and dependency choices. That project is AGPL v3, so this implementation must not copy its source code, UI layout, component structure, assets, text, or visual design.

## Scope

Included:

- Login to an existing EasyNode server.
- Persist server address and username by default.
- Save password only when the user explicitly enables it.
- Store password, token, session cookie, and a mobile-generated device identifier in platform secure storage.
- Generate a per-install `deviceId` (UUID v4) the first time the app launches; persist it in secure storage and send it with every login.
- Fetch server data from the existing `/api/v1/host-list` API.
- Show a mobile server list with a connect action.
- Request SSH connection parameters through one new mobile-only server API.
- Use native Flutter/Dart SSH for terminal connections.
- Support password authentication, private-key authentication, and credential-backed hosts that resolve to one of those two methods.
- Support Android and iOS from one Flutter codebase, with small platform configuration differences.

Excluded from the first release:

- Server add/edit/delete flows.
- SFTP.
- RDP.
- Jump hosts and proxy servers.
- Multi-tab terminals.
- Suspended terminal sessions.
- Script library, Docker, one-key commands, AI integrations, and other Web-only features.
- A separate mobile auth/session protocol.

## Architecture

The Flutter app uses one shared Dart codebase for Android and iOS. Platform-specific work is limited to network permissions, HTTP cleartext policy, ATS exceptions, and secure-storage plugin configuration.

The app reuses existing EasyNode APIs where possible:

- `GET /api/v1/get-pub-pem`
- `POST /api/v1/login`
- `GET /api/v1/host-list`
- optionally `DELETE /api/v1/revoke-login/:deviceId`

Only one new server API is required:

- `POST /api/v1/mobile/ssh-connection`

The new endpoint exists because `/host-list` intentionally clears `password` and `privateKey`, while native SSH requires the app to receive decrypted connection parameters at connect time.

## Login Flow

The login page contains:

- server address, for example `http://192.168.1.10:8082`
- username
- password
- optional MFA2 token
- save-password switch
- login expiry choice: temporary, current day, three days, seven days

Server address and username are saved in ordinary app storage because other normal apps cannot read the app sandbox directly on Android or iOS. They are not treated as high-sensitivity secrets.

Password is saved only when the user enables save-password. Saved passwords must use platform secure storage:

- Android: Keystore-backed encrypted storage through `flutter_secure_storage`
- iOS: Keychain through `flutter_secure_storage`

Token, session cookie, and the mobile `deviceId` also use secure storage.

The first release does not implement public-key fingerprint binding or change-detection. The RSA public key returned from `/api/v1/get-pub-pem` is still required, because the login password and the per-request temporary AES key are both encrypted with it.

On login:

1. Validate and normalize the server address.
2. If the address uses HTTP, show a strong warning before any login request.
3. Ensure a `deviceId` (UUID v4) exists in secure storage; generate and persist one if missing.
4. Fetch the server public key from `/api/v1/get-pub-pem`.
5. Encrypt the password with the server public key.
6. Call `/api/v1/login` with the existing Web-compatible payload, including the persisted `deviceId`.
7. Store returned token and received `session` cookie in secure storage.
8. Load the server list with `/api/v1/host-list`.

The HTTP warning should be explicit: HTTP can expose the login token and session cookie, allowing an attacker to take over the app session. The encrypted SSH-parameter response does not replace HTTPS. The warning is shown only when the configured server address uses HTTP; it is not used for any other purpose.

## Server List

The server list uses the existing `/api/v1/host-list` response. The app consumes only the fields needed for a mobile list:

- `id`
- `name`
- `host`
- `port`
- `username`
- `authType`
- `group`
- `tag`
- `expired`
- `isConfig`

The initial UI is intentionally simple and distinct from the reference project:

- title: server name
- subtitle: `username@host:port`
- small metadata chips or labels for auth type, group, and configured status
- primary action: connect

The list supports pull-to-refresh. If the auth configuration is missing, the connect action is disabled or explains that the server has no SSH credentials configured.

When a protected API returns 401 or 403, the app clears token and session and returns to the login page while preserving server address, username, and password-save preference.

## SSH Credential API

Endpoint:

```http
POST /api/v1/mobile/ssh-connection
```

Request body:

```json
{
  "hostId": "host id",
  "encryptedKey": "RSA encrypted temporary key"
}
```

Rules:

- The endpoint uses the existing Koa auth middleware.
- It requires the existing `token` header and `session` cookie.
- `hostId` must exist.
- The client generates a fresh 32-byte random key, base64-encodes it, then RSA-encrypts the base64 string with the server public key. The server RSA-decrypts to a utf8 string and base64-decodes that string back into the 32-byte key. This round-trip preserves binary key bytes through the existing RSA helper.
- The decrypted temporary key must be 32 bytes after decoding.
- The temporary key is used only for this response.
- On any failure, the response message must be a generic string; details only go to the server log.

Server behavior:

1. Verify the existing EasyNode login state.
2. Resolve the host record.
3. Resolve `authType=credential` into the underlying credential record.
4. Decrypt the stored password or private key using the existing EasyNode database encryption logic.
5. Build a minimal SSH connection payload.
6. Encrypt that payload with AES-256-GCM using the client temporary key.
7. Return only encrypted fields.

Encrypted response shape:

```json
{
  "status": 200,
  "msg": "success",
  "data": {
    "alg": "AES-256-GCM",
    "iv": "base64 iv",
    "tag": "base64 auth tag",
    "ciphertext": "base64 ciphertext"
  }
}
```

Plaintext payload after mobile decryption:

```json
{
  "hostId": "host id",
  "name": "server name",
  "host": "1.2.3.4",
  "port": 22,
  "username": "root",
  "authType": "privateKey",
  "password": "",
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----...",
  "passphrase": ""
}
```

For password authentication, `authType` is `password` and `password` is populated. For private-key authentication, `privateKey` is populated and `passphrase` may be populated.

No response body outside the AES-GCM ciphertext may contain SSH passwords, private keys, or passphrases.

## Encryption Design

The first release uses a pragmatic encryption envelope for sensitive SSH parameters:

- The app generates a fresh 32-byte random key for each SSH-parameter request.
- The app RSA-encrypts this key using the EasyNode public key from `/get-pub-pem`.
- The server decrypts the key with its private key.
- The server AES-256-GCM-encrypts the SSH parameters using that key.
- The app decrypts the response and immediately starts the SSH connection.
- The temporary key and SSH parameters stay in memory only.

This protects the SSH credential response body from passive network capture. It does not fully protect HTTP users because the existing `token + session` login state can still be captured on HTTP. That is why the login flow must warn before HTTP use.

The first release may use the current RSA mode for compatibility with the existing login flow. AES for the new response envelope should use Node's native `crypto` module rather than the existing CryptoJS passphrase mode.

## Terminal

The terminal page uses:

- `dartssh2` for native SSH connections.
- the pub.dev `xterm` package for terminal rendering. The package is MIT licensed and may be used as a normal dependency.
- a project-owned `SshTerminalController` to bridge `dartssh2` shell streams to xterm input and output.

The app must not copy terminal page code, local package code, UI layout, or component organization from the AGPL reference project.

The first terminal page provides:

- server name and connection status
- full-height terminal area
- minimal mobile toolbar with `Esc`, `Ctrl`, `Tab`, paste, disconnect, and navigation keys
- reconnect and return-to-list actions after disconnect

Resize should be sent to the SSH shell when the terminal viewport changes.

## Flutter Structure

Proposed structure:

```text
mobile/lib/
  main.dart
  app.dart

  core/
    api/
      api_client.dart
      api_result.dart
      cookie_store.dart
    crypto/
      rsa_crypto.dart
      aes_gcm_crypto.dart
    storage/
      app_storage.dart
      secure_storage.dart
      device_id.dart
    ssh/
      ssh_connection_config.dart
      ssh_terminal_controller.dart
    utils/
      validators.dart
      jwt_expiry.dart

  features/
    auth/
      login_page.dart
      login_controller.dart
      auth_session.dart
    servers/
      server_list_page.dart
      server_model.dart
      server_repository.dart
    terminal/
      terminal_page.dart
      terminal_toolbar.dart
```

The app should avoid heavy generated architecture for the first release. A simple controller/store approach is enough. `ChangeNotifier` or another small state layer is preferred over a large framework until the app grows.

Candidate dependencies:

- `dio`
- `cookie_jar`
- `dio_cookie_manager`
- `flutter_secure_storage`
- `shared_preferences`
- `pointycastle` or another suitable crypto package
- `dartssh2`
- `xterm`

Dependencies must be checked for permissive licenses before implementation.

## Platform Policy

Android:

- Add `INTERNET` permission.
- Allow cleartext HTTP for user-provided self-hosted servers.
- Show in-app HTTP warning before login.

iOS:

- Add ATS exceptions required for user-provided HTTP servers.
- Keep in-app wording clear that HTTPS is recommended.
- For App Store review, explain that users connect to their own self-hosted EasyNode instance and HTTP is retained for LAN and legacy deployment compatibility.

HTTPS with a valid certificate is the recommended path. Self-signed HTTPS can be supported later with certificate-fingerprint binding if needed, but the first implementation does not require a custom TLS trust manager.

## Error Handling

Login:

- Invalid address: block locally.
- HTTP address: show strong warning before login.
- Public key fetch failure: show server/network error.
- Login failure: show the server message and keep address and username.
- 401/403: clear token/session and return to login.

Server list:

- Fetch failure: show retry.
- Empty list: show empty state.
- Missing SSH auth: disable connect or explain the reason.
- Credential-backed host: allow connect; the server resolves it.

Terminal:

- SSH-parameter API failure: show error and allow return.
- Decryption failure: stop before SSH and show error.
- SSH auth failure: show error and allow retry.
- Network disconnect: write disconnect status to the terminal and provide reconnect/return.
- App backgrounding: no explicit keepalive in first release.

## Testing

Dart unit tests:

- login-expiry conversion
- server address normalization
- HTTP risk detection
- deviceId generation and persistence
- AES-GCM decrypt/encrypt helpers
- host-list JSON model mapping
- SSH credential encrypted response decoding

Flutter widget tests:

- login validation
- HTTP warning flow
- save-password switch behavior
- server list rendering
- disabled connect action for unconfigured hosts

Node server tests:

- missing token/session rejects `POST /api/v1/mobile/ssh-connection`
- missing or unknown `hostId` rejects
- unconfigured auth rejects
- password host returns encrypted response
- private-key host returns encrypted response
- credential-backed host returns encrypted response
- response body never includes raw password/private key/passphrase outside ciphertext

Manual acceptance:

- Android HTTP login shows warning.
- Android login succeeds against a local EasyNode server.
- Android server list loads from `/host-list`.
- Android password SSH connects.
- Android private-key SSH connects.
- Token expiration returns to login with address and username retained.
- iOS builds with compatible code and required network configuration.
