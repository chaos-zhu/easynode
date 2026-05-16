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
