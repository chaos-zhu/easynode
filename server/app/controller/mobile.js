const crypto = require('crypto')
const { RSADecryptAsync } = require('../utils/encrypt')

function encryptJsonForMobile(payload, key) {
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

function normalizeMobileAuthPayload(hostId, name, authInfo = {}) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported mobile ssh auth type: ${ authType || 'empty' }`)
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

function normalizeMobileProxy(proxy = {}) {
  if (!['socks5', 'http'].includes(proxy.type)) {
    throw new Error(`unsupported mobile proxy type: ${ proxy.type || 'empty' }`)
  }

  return {
    id: proxy.id || proxy._id || '',
    name: proxy.name || '',
    type: proxy.type,
    host: proxy.host || '',
    port: Number(proxy.port),
    username: proxy.username || '',
    password: proxy.password || ''
  }
}

function normalizeMobileJumpHost({ hostId, name, ...authInfo }) {
  return normalizeMobileAuthPayload(hostId, name, authInfo)
}

function toMobileSshPayload(hostId, name, authInfo, topology = {}) {
  const payload = normalizeMobileAuthPayload(hostId, name, authInfo)
  const proxyType = topology.proxyType || ''

  if (proxyType === 'proxyServer') {
    if (!topology.proxy) {
      throw new Error('mobile proxy is required')
    }

    return {
      ...payload,
      proxyType,
      proxy: normalizeMobileProxy(topology.proxy),
      jumpHosts: []
    }
  }

  if (proxyType === 'jumpHosts') {
    if (!Array.isArray(topology.jumpHosts) || topology.jumpHosts.length === 0) {
      throw new Error('mobile jump host chain is empty')
    }

    return {
      ...payload,
      proxyType,
      proxy: null,
      jumpHosts: topology.jumpHosts.map(normalizeMobileJumpHost)
    }
  }

  if (proxyType) {
    throw new Error(`unsupported mobile proxy type: ${ proxyType }`)
  }

  return {
    ...payload,
    proxyType: '',
    proxy: null,
    jumpHosts: []
  }
}

async function getMobileConnectionTopology(hostInfo = {}) {
  const { proxyType } = hostInfo

  if (proxyType === 'proxyServer') {
    const { getProxyConfig } = require('../socket/terminal')
    return {
      proxyType,
      proxy: await getProxyConfig(hostInfo.proxyServer)
    }
  }

  if (proxyType === 'jumpHosts') {
    const jumpHosts = Array.isArray(hostInfo.jumpHosts) ? hostInfo.jumpHosts : []
    const { getConnectionOptions } = require('../socket/terminal')
    return {
      proxyType,
      jumpHosts: await Promise.all(jumpHosts.map(async (jumpHostId) => {
        const { authInfo, name } = await getConnectionOptions(jumpHostId)
        return {
          hostId: jumpHostId,
          name,
          ...authInfo
        }
      }))
    }
  }

  return {}
}

async function getMobileSshConnection({ request, res }) {
  try {
    const { hostId, encryptedKey } = request.body || {}
    if (!hostId || !encryptedKey) {
      return res.fail({ msg: 'missing params' })
    }

    const tempKeyText = await RSADecryptAsync(encryptedKey)
    const tempKey = Buffer.from(tempKeyText, 'base64')
    const { getConnectionOptions } = require('../socket/terminal')
    const { authInfo, name, hostInfo } = await getConnectionOptions(hostId)
    const topology = await getMobileConnectionTopology(hostInfo)
    const payload = toMobileSshPayload(hostId, name, authInfo, topology)
    const data = encryptJsonForMobile(payload, tempKey)

    return res.success({ data, msg: 'success' })
  } catch (error) {
    logger.error('getMobileSshConnection error:', error.message)
    return res.fail({ msg: error.message || 'mobile ssh connection failed' })
  }
}



module.exports = {
  getMobileSshConnection
}
