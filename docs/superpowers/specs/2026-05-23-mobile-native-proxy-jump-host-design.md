# Mobile Native Proxy and Jump Host Support Design

## Context

The web terminal connects through `server/app/socket/terminal.js`. The server reads the target host, decrypts credentials, applies `proxyType`, and either opens a direct SSH connection, creates a proxy tunnel, or connects through jump hosts before handing the final socket to `ssh2`.

The mobile terminal currently connects locally with `dartssh2`:

```text
mobile -> target SSH
```

That preserves a native terminal experience, but it means server-side proxy and jump-host handling does not apply. Mobile must support the same connection topology locally:

```text
mobile -> proxy/jump chain -> target SSH
```

## Goals

- Keep mobile terminal connections local and native, including proxy and jump-host scenarios.
- Support the existing host fields: `proxyType`, `proxyServer`, and `jumpHosts`.
- Reuse the existing encrypted `/mobile/ssh-connection` response envelope for sensitive connection details.
- Preserve current direct SSH behavior for hosts without proxy or jump hosts.
- Provide clear errors for proxy, jump-host, and target-host failures.

## Non-Goals

- Do not route mobile terminal sessions through the server terminal websocket.
- Do not change web terminal behavior.
- Do not redesign server host, proxy, or credential storage.
- Do not implement mobile RDP proxying in this change.

## Connection Modes

### Direct

When `proxyType` is empty, the mobile app connects as it does today:

```text
SSHSocket.connect(target.host, target.port)
SSHClient(socket, target auth)
```

Unsupported mobile proxy modes should fail explicitly instead of silently falling back to direct connection.

### SOCKS5 Proxy

When `proxyType === 'proxyServer'` and the selected proxy has `type === 'socks5'`, the mobile app opens a TCP socket to the proxy, performs SOCKS5 negotiation, asks the proxy to connect to the target host and port, and passes the established tunnel to `dartssh2`.

Supported SOCKS5 authentication:

- No authentication
- Username/password authentication

### HTTP Proxy

HTTP CONNECT can be added after SOCKS5 and jump hosts. If the server returns an HTTP proxy before mobile support exists, mobile should return a clear unsupported error.

### Jump Hosts

When `proxyType === 'jumpHosts'`, the mobile app connects to each jump host in order. Each jump host opens a `direct-tcpip` style channel to the next hop. The final target `SSHClient` is created over the last forwarded channel.

Single and multi-hop chains use the same algorithm:

```text
connect jump1
jump1 opens channel to jump2 or target
connect next SSHClient over that channel
repeat until target
connect final target SSHClient
```

All intermediate jump `SSHClient` instances must stay alive for the target session lifetime and must be closed when the terminal disconnects.

## Server Payload Design

`/mobile/ssh-connection` should continue to return an AES-GCM encrypted payload. The plaintext payload expands from target auth only to target auth plus connection topology.

Direct example:

```json
{
  "hostId": "target",
  "name": "prod",
  "host": "1.2.3.4",
  "port": 22,
  "username": "root",
  "authType": "privateKey",
  "password": "",
  "privateKey": "...",
  "passphrase": "",
  "proxyType": "",
  "proxy": null,
  "jumpHosts": []
}
```

SOCKS5 example:

```json
{
  "hostId": "target",
  "name": "prod",
  "host": "1.2.3.4",
  "port": 22,
  "username": "root",
  "authType": "password",
  "password": "...",
  "privateKey": "",
  "passphrase": "",
  "proxyType": "proxyServer",
  "proxy": {
    "id": "proxy1",
    "name": "office socks",
    "type": "socks5",
    "host": "proxy.example.com",
    "port": 1080,
    "username": "",
    "password": ""
  },
  "jumpHosts": []
}
```

Jump-host example:

```json
{
  "hostId": "target",
  "name": "prod",
  "host": "10.0.0.20",
  "port": 22,
  "username": "root",
  "authType": "privateKey",
  "password": "",
  "privateKey": "...",
  "passphrase": "",
  "proxyType": "jumpHosts",
  "proxy": null,
  "jumpHosts": [
    {
      "hostId": "jump1",
      "name": "jump-1",
      "host": "203.0.113.10",
      "port": 22,
      "username": "root",
      "authType": "password",
      "password": "...",
      "privateKey": "",
      "passphrase": ""
    }
  ]
}
```

The server must resolve credentials for jump hosts the same way it resolves the target host. If a jump host uses `authType === 'credential'`, the payload should contain the resolved concrete auth type and decrypted secret.

## Mobile Architecture

Introduce a transport layer between `SshTerminalController` and `dartssh2`.

```text
SshTerminalController
  -> SshTransportFactory.open(config)
      -> DirectSshTransport
      -> Socks5SshTransport
      -> JumpHostSshTransport
  -> SSHClient(transport.socket, target auth)
```

### Models

Extend `SshConnectionConfig` with:

- `proxyType`
- `SshProxyConfig? proxy`
- `List<SshJumpHostConfig> jumpHosts`

Add a shared auth shape for target and jump hosts:

- `hostId`
- `name`
- `host`
- `port`
- `username`
- `authType`
- `password`
- `privateKey`
- `passphrase`
- `privateKeyPassphrase`

`privateKeyPassphrase` should keep the existing behavior: empty or whitespace passphrases become `null`.

### Transport Handle

`SshTransportFactory.open` should return a handle containing:

- The stream/socket used by the final target `SSHClient`.
- Any intermediate SSH clients that must remain alive.
- A `close()` method that shuts down intermediate clients and sockets in reverse order.

This prevents `SshTerminalController` from knowing how a tunnel was built while still letting it clean up correctly.

## Error Handling

Errors should identify the failing layer:

- `SOCKS5 proxy connection failed`
- `SOCKS5 authentication failed`
- `SOCKS5 target connection failed`
- `Jump host connection failed: <name>`
- `Jump host authentication failed: <name>`
- `Jump host forwarding failed: <from> -> <to>`
- `Target SSH authentication failed`
- `Unsupported mobile proxy type: http`

The terminal page can display the error in the existing terminal output style.

## Security

Mobile already receives decrypted target SSH credentials for local native SSH. This design expands that scope to proxy credentials and jump-host credentials only when the selected target host requires them.

Mitigations:

- Keep using the existing RSA temporary key plus AES-GCM encrypted response envelope.
- Do not persist decrypted proxy or jump-host credentials.
- Keep decrypted payload lifetime scoped to the connection attempt.
- Do not include proxy credentials or jump-host credentials in list APIs.
- Avoid logging decrypted secrets on server or mobile.

## Testing

### Server

- `toMobileSshPayload` returns direct payload with empty proxy and jump-host fields.
- `toMobileSshPayload` returns SOCKS5 proxy details for `proxyType === 'proxyServer'`.
- `toMobileSshPayload` returns resolved jump-host auth details for `proxyType === 'jumpHosts'`.
- Missing proxy or jump host produces a clear error.
- Credential-based target and jump hosts resolve to concrete `password` or `privateKey` auth.

### Mobile

- `SshConnectionConfig.fromJson` parses direct, SOCKS5, and jump-host payloads.
- Empty passphrases are converted to `null` for target and jump-host private keys.
- `SshTransportFactory` selects direct, SOCKS5, or jump-host transport based on `proxyType`.
- SOCKS5 handshake supports no-auth and username/password modes.
- Jump-host transport keeps intermediate clients alive and closes them on disconnect.
- Unsupported proxy types fail explicitly.

## Rollout

1. Extend server mobile payload generation and tests.
2. Extend mobile config models and parser tests.
3. Add `SshTransportFactory` with direct transport only and migrate current controller to use it.
4. Add SOCKS5 transport and tests.
5. Add jump-host transport and tests.
6. Add user-facing error messages.
7. Add HTTP CONNECT proxy support later if needed.
