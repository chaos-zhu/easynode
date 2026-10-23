import { test } from 'node:test'
import assert from 'node:assert/strict'
import { nativeRdpPayload } from '../app/utils/native-rdp-payload.js'

const connection = {
  name: 'Windows', hostInfo: { connectType: 'rdp' },
  authInfo: { host: '10.0.0.2', port: 3389, username: 'DOMAIN\\user', authType: 'password', password: 'secret' }
}
test('RDP payload requires active Plus and an RDP/password host', () => {
  assert.throws(() => nativeRdpPayload('a', connection, false), /Plus/)
  assert.throws(() => nativeRdpPayload('a', { ...connection, hostInfo: { connectType: 'ssh' } }, true), /not an RDP/)
  assert.throws(() => nativeRdpPayload('a', { ...connection, authInfo: { ...connection.authInfo, authType: 'privateKey' } }, true), /password authentication/)
  for (const port of [0, 65536, 'bad']) {
    assert.throws(() => nativeRdpPayload('a', { ...connection, authInfo: { ...connection.authInfo, port } }, true), /invalid/)
  }
})
test('payload includes only required credentials and preserves domain username', () => {
  assert.deepEqual(nativeRdpPayload('a', connection, true), {
    hostId: 'a', name: 'Windows', host: '10.0.0.2', port: 3389,
    username: 'DOMAIN\\user', authType: 'password', password: 'secret'
  })
})
