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

function testRejectsUnsupportedAuth() {
  assert.throws(() => toMobileSshPayload('h3', 'unsupported', {
    host: '10.0.0.4',
    port: 22,
    username: 'root',
    authType: 'keyboard'
  }), /unsupported mobile ssh auth type/)
}

function testSocks5ProxyPayload() {
  const payload = toMobileSshPayload('h4', 'proxied', {
    host: '10.0.0.5',
    port: '2200',
    username: 'deploy',
    authType: 'password',
    password: 'secret'
  }, {
    proxyType: 'proxyServer',
    proxy: {
      id: 'p1',
      name: 'edge-proxy',
      type: 'socks5',
      host: '127.0.0.1',
      port: '1080',
      username: 'proxy-user',
      password: 'proxy-pass'
    }
  })

  assert.deepStrictEqual(payload.proxy, {
    id: 'p1',
    name: 'edge-proxy',
    type: 'socks5',
    host: '127.0.0.1',
    port: 1080,
    username: 'proxy-user',
    password: 'proxy-pass'
  })
  assert.strictEqual(payload.proxyType, 'proxyServer')
  assert.deepStrictEqual(payload.jumpHosts, [])
}

function testJumpHostsPayload() {
  const payload = toMobileSshPayload('h5', 'target', {
    host: '10.0.0.6',
    port: 22,
    username: 'app',
    authType: 'privateKey',
    privateKey: 'TARGET_KEY',
    password: 'ignored',
    passphrase: ''
  }, {
    proxyType: 'jumpHosts',
    jumpHosts: [
      {
        hostId: 'j1',
        name: 'bastion',
        host: '10.0.0.7',
        port: '2222',
        username: 'jump',
        authType: 'password',
        password: 'jump-pass',
        privateKey: 'ignored'
      }
    ]
  })

  assert.strictEqual(payload.proxyType, 'jumpHosts')
  assert.strictEqual(payload.proxy, null)
  assert.deepStrictEqual(payload.jumpHosts, [
    {
      hostId: 'j1',
      name: 'bastion',
      host: '10.0.0.7',
      port: 2222,
      username: 'jump',
      authType: 'password',
      password: 'jump-pass',
      privateKey: '',
      passphrase: ''
    }
  ])
}

function testRejectsUnsupportedProxyType() {
  assert.throws(() => toMobileSshPayload('h6', 'bad-proxy', {
    host: '10.0.0.8',
    port: 22,
    username: 'root',
    authType: 'password',
    password: 'secret'
  }, {
    proxyType: 'proxyServer',
    proxy: {
      id: 'p2',
      name: 'http-proxy',
      type: 'http',
      host: '127.0.0.1',
      port: 8080
    }
  }), /unsupported mobile proxy type: http/)
}

function testRejectsEmptyJumpHostChain() {
  assert.throws(() => toMobileSshPayload('h7', 'empty-jumps', {
    host: '10.0.0.9',
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
testRejectsUnsupportedAuth()
testSocks5ProxyPayload()
testJumpHostsPayload()
testRejectsUnsupportedProxyType()
testRejectsEmptyJumpHostChain()
console.log('test-mobile-ssh-payload passed')
