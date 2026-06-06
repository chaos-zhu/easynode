const crypto = require('crypto')
const path = require('path')
const { RSADecryptAsync } = require('../utils/encrypt')
const decryptAndExecuteAsync = require('../utils/decrypt-file')

function encryptJsonForNative(payload, key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new Error('temporary key must be 32 bytes')
  }
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

function normalizeNativeAuthPayload(hostId, name, authInfo = {}) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported native ssh auth type: ${ authType || 'empty' }`)
  }

  return {
    hostId,
    name,
    host: host || '',
    port: Number(port),
    username: username || '',
    authType,
    password: authType === 'password' ? authInfo.password || '' : '',
    privateKey: authType === 'privateKey' ? authInfo.privateKey || '' : '',
    passphrase: authType === 'privateKey' ? authInfo.passphrase || '' : ''
  }
}

async function buildNativeTopology(hostInfo = {}) {
  const { proxyType } = hostInfo
  if (!['proxyServer', 'jumpHosts'].includes(proxyType)) {
    return { proxyType: '', proxy: null, jumpHosts: [] }
  }

  let { getConnectionHelper } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (getConnectionHelper) {
    const config = await getConnectionHelper(proxyType, hostInfo, normalizeNativeAuthPayload)
    return config
  } else {
    throw new Error('跳板机&代理服务为Plus功能')
  }
}

async function getNativeSshConnection({ request, res }) {
  try {
    const { hostId, encryptedKey } = request.body || {}
    if (!hostId || !encryptedKey) {
      return res.fail({ msg: 'missing params' })
    }

    const tempKeyText = await RSADecryptAsync(encryptedKey)
    const tempKey = Buffer.from(tempKeyText, 'base64')
    const { getConnectionOptions } = require('../socket/terminal')
    const { authInfo, name, hostInfo } = await getConnectionOptions(hostId)
    const payload = {
      ...normalizeNativeAuthPayload(hostId, name, authInfo),
      ...await buildNativeTopology(hostInfo)
    }
    const data = encryptJsonForNative(payload, tempKey)

    return res.success({ data, msg: 'success' })
  } catch (error) {
    logger.error('getNativeSshConnection error:', error.message)
    return res.fail({ msg: error.message || 'native ssh connection failed' })
  }
}

module.exports = {
  getNativeSshConnection
}
