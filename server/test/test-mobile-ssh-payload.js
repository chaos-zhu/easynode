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
