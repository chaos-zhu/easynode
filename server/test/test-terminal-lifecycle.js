import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'

const source = readFileSync(new URL('../app/socket/terminal.js', import.meta.url), 'utf8')
const creationSource = source.slice(source.indexOf('async function createTerminal('), source.indexOf('\n/**\n * 恢复挂起'))
const socketSource = source.slice(source.indexOf('function resumeSession('), source.indexOf('export default'))
const logger = { info() {}, warn() {}, error() {} }
const deferred = () => {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}
const flush = async () => { for (let index = 0; index < 12; index++) await Promise.resolve() }

class Socket extends EventEmitter {
  connected = true
  id = 'test-socket'
  sent = []
  emit(event, ...args) { this.sent.push({ event, args }); return this }
  async receive(event, ...args) {
    if (event === 'disconnect') this.connected = false
    await Promise.all(this.listeners(event).map(listener => listener(...args)))
  }
}
class Client extends EventEmitter {
  ended = false
  connects = 0
  connect() { this.connects++; return this }
  end() { this.ended = true }
}
function createHarness({ host, credentials, proxy, shell, interactive = true } = {}) {
  const socket = new Socket()
  const client = new Client()
  const options = { host: 'example.test' }
  const stream = { closed: false, close() { this.closed = true } }
  const createTerminal = runInNewContext(creationSource + '\n;createTerminal', {
    logger,
    sendNoticeAsync() {},
    hostListDB: { findOneAsync: () => host?.promise || Promise.resolve({ host: 'example.test', authType: 'password' }) },
    getConnectionOptions: () => credentials?.promise || Promise.resolve({ authInfo: options }),
    handleProxyAndJumpHostConnection: () => proxy?.promise || Promise.resolve({ jumpSshClients: [] }),
    createInteractiveShell: () => shell?.promise || Promise.resolve(stream)
  })
  const result = createTerminal('host', socket, client, interactive)
  return { socket, client, options, stream, result }
}

// 查询凭据、代理准备、SSH 握手和 shell 创建的各阶段均可被取消。
const host = deferred()
const beforeHost = createHarness({ host })
await beforeHost.socket.receive('disconnect', 'transport close')
assert.equal(await beforeHost.result, null)
host.resolve({ host: 'example.test', authType: 'password' })
await flush()
assert.equal(beforeHost.client.connects, 0)

const credentials = deferred()
const beforeCredentials = createHarness({ credentials })
await flush()
await beforeCredentials.socket.receive('disconnect', 'transport close')
assert.equal(await beforeCredentials.result, null)
credentials.resolve({ authInfo: beforeCredentials.options })
await flush()
assert.equal(beforeCredentials.client.connects, 0)

const proxy = deferred()
const beforeProxy = createHarness({ proxy })
await flush()
await beforeProxy.socket.receive('disconnect', 'transport close')
assert.equal(await beforeProxy.result, null)
let proxyClosed = false
const jumpClient = new Client()
beforeProxy.options.sock = { destroy() { proxyClosed = true } }
proxy.resolve({ jumpSshClients: [jumpClient] })
await flush()
assert.equal(proxyClosed, true, '取消后才建立的代理通道也必须关闭')
assert.equal(jumpClient.ended, true)
assert.equal(beforeProxy.client.connects, 0)

const handshake = createHarness()
await flush()
assert.equal(handshake.client.connects, 1)
await handshake.socket.receive('disconnect', 'transport close')
assert.equal(await handshake.result, null)
assert.equal(handshake.client.ended, true)
assert.equal(handshake.socket.listenerCount('disconnect'), 0)

const shell = deferred()
const beforeShell = createHarness({ shell })
await flush()
beforeShell.client.emit('ready')
await beforeShell.socket.receive('disconnect', 'transport close')
assert.equal(await beforeShell.result, null)
shell.resolve(beforeShell.stream)
await flush()
assert.equal(beforeShell.stream.closed, true, '迟到的 shell 不能成为孤立会话')

const success = createHarness()
await flush()
success.client.emit('ready')
assert.equal((await success.result).stream, success.stream)
assert.equal(success.client.ended, false)
assert.equal(success.stream.closed, false)
assert.equal(success.socket.listenerCount('disconnect'), 0, '创建成功后由会话管理器接管释放')

// SSH 已报错或关闭时，尚未返回的 shell 仍需回收。
for (const event of ['error', 'close']) {
  const pendingShell = deferred()
  const failed = createHarness({ shell: pendingShell })
  await flush()
  failed.client.emit('ready')
  failed.client.emit(event, new Error('connection lost'))
  assert.equal(await failed.result, null)
  pendingShell.resolve(failed.stream)
  await flush()
  assert.equal(failed.stream.closed, true, `${ event } 后迟到的 shell 必须关闭`)
  assert.equal(failed.client.ended, true)
}

// Docker / 状态监控共用非交互连接；成功时保留连接，失败时正常返回。
const noninteractive = createHarness({ interactive: false })
await flush()
assert.equal(noninteractive.socket.listenerCount('disconnect'), 0)
noninteractive.client.emit('ready')
assert.equal((await noninteractive.result).connectionOptions, noninteractive.options)
assert.equal(noninteractive.client.ended, false)
const noninteractiveFailure = createHarness({ interactive: false })
await flush()
noninteractiveFailure.client.emit('error', new Error('authentication failed'))
assert.equal(await noninteractiveFailure.result, null)
assert.equal(noninteractiveFailure.client.ended, true)
assert.equal(noninteractiveFailure.socket.sent.filter(event => event.event === 'terminal_connect_fail').length, 1)

function createServerHarness(createTerminal) {
  const sessions = new Map()
  let onConnection
  let created = 0
  const manager = {
    getSession: key => sessions.get(key),
    findSuspendedSession: () => null,
    getSessionBySocket: () => null,
    createSession: options => { created++; return { ...options, sessionId: 'new-session' } },
    bindSocket() {},
    resumeSession: () => null
  }
  const createServerIo = runInNewContext(socketSource + '\n;createServerIo', {
    logger, sessionManager: manager, SessionStatus: { SUSPENDED: 'suspended' },
    SSHClient: Client, createTerminal, normalizeTerminalSize: size => size,
    keyDB: { findOneAsync: async () => ({ _id: 'user' }) }
  })
  createServerIo({ on: (_, callback) => { onConnection = callback } })
  return { sessions, connect: onConnection, created: () => created }
}

// 防御成功结果与 socket 断开的竞态：会话注册前再次检查连接。
const late = deferred()
const server = createServerHarness(() => late.promise)
const disconnected = new Socket()
await server.connect(disconnected)
const request = disconnected.receive('ws_terminal', { hostId: 'host', forceNew: true })
await disconnected.receive('disconnect', 'transport close')
let lateClosed = false
const lateJump = new Client()
late.resolve({ stream: { close() { lateClosed = true } }, jumpSshClients: [lateJump] })
await request
assert.equal(server.created(), 0)
assert.equal(lateClosed, true)
assert.equal(lateJump.ended, true)

// 失效会话先通知前端，再创建新 shell，不能停在永久失败状态。
for (const existing of [false, true]) {
  let connections = 0
  const fallback = createServerHarness(async () => { connections++; return {} })
  if (existing) fallback.sessions.set('expired', { userId: 'user', hostId: 'host' })
  const socket = new Socket()
  await fallback.connect(socket)
  await socket.receive('ws_terminal', { hostId: 'host', resumeSessionId: 'expired' })
  assert.equal(connections, 1)
  assert.equal(fallback.created(), 1)
  assert.equal(socket.sent.filter(event => event.event === 'terminal_resume_failed').length, 1)
  assert.ok(socket.sent.some(event => event.event === 'session_created'))
}
console.log('终端建连取消、迟到资源回收和失效会话重建回归测试通过')
