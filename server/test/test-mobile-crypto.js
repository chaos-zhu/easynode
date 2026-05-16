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
