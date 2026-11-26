import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import jwt from 'jsonwebtoken'

const originalCwd = process.cwd()
const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'easynode-ws-auth-'))
process.chdir(tempRoot)
global.logger = { warn() {}, error() {} }

try {
  const { KeyDB, SessionDB } = await import('../app/utils/db-class.js')
  const { AESEncryptAsync, SHA256Encrypt } = await import('../app/utils/encrypt.js')
  const { verifyWsAuthSync } = await import('../app/utils/verify-auth.js')

  const key = await new KeyDB().getInstance().insertAsync({
    jwtToken: 'test-jwt-key',
    commonKey: 'test-encryption-key'
  })
  const session = 'test-session'
  const jwtToken = jwt.sign({}, `${ key.jwtToken }-${ key._id }`)
  const token = await AESEncryptAsync(jwtToken)
  await new SessionDB().getInstance().insertAsync({
    session,
    tokenHash: SHA256Encrypt(jwtToken),
    revoked: false,
    expireAt: Date.now() + 60_000
  })

  function makeSocket(headers, auth = {}) {
    return { conn: { remoteAddress: '127.0.0.1' }, handshake: { headers, auth }, data: {} }
  }

  const authenticate = socket => new Promise(resolve => verifyWsAuthSync(socket, resolve))

  const failingSocket = makeSocket({
    get cookie() { throw new URIError('simulated cookie decode failure') }
  })
  assert.match((await authenticate(failingSocket))?.message, /^Authentication Failed$/)
  assert.equal(failingSocket.data.authSession, undefined)

  const headers = { cookie: `session=${ session }` }
  assert.match((await authenticate(makeSocket(headers)))?.message, /^No Token$/)

  const validSocket = makeSocket(headers, { token })
  assert.equal(await authenticate(validSocket), undefined)
  assert.equal(validSocket.data.authSession, session)
  console.log('WebSocket 鉴权异常处理测试通过')
} finally {
  process.chdir(originalCwd)
  await fs.rm(tempRoot, { recursive: true, force: true })
}
