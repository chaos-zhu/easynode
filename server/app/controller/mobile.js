const { RSADecryptAsync } = require('../utils/encrypt')
const { encryptJsonForMobile } = require('../utils/mobile-crypto')
const { HostListDB } = require('../utils/db-class')

// `getConnectionOptions` and `getProxyConfig` are lazily required inside
// functions. Loading `../socket/terminal` at module scope pulls in
// `terminal-session`, which expects `global.logger` to exist after app boot.
const hostListDB = new HostListDB().getInstance()

function normalizePort(port) {
  const numericPort = Number(port)
  return Number.isFinite(numericPort) && numericPort > 0 ? numericPort : 22
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
    port: normalizePort(port),
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
    port: normalizePort(proxy.port),
    username: proxy.username || '',
    password: proxy.password || ''
  }
}

function normalizeMobileJumpHost(jumpHost) {
  const authInfo = jumpHost.authInfo || jumpHost
  return normalizeMobileAuthPayload(
    jumpHost.hostId || jumpHost._id || authInfo.hostId || authInfo._id,
    jumpHost.name || authInfo.name,
    authInfo
  )
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
    const { authInfo, name } = await getConnectionOptions(hostId)
    const hostInfo = await hostListDB.findOneAsync({ _id: hostId })
    if (!hostInfo) {
      throw new Error(`Host with ID ${ hostId } not found`)
    }
    const topology = await getMobileConnectionTopology(hostInfo)
    const payload = toMobileSshPayload(hostId, name, authInfo, topology)
    const data = encryptJsonForMobile(payload, tempKey)

    return res.success({ data, msg: 'success' })
  } catch (error) {
    // Detail goes to the server log; the wire response stays generic.
    logger.error('getMobileSshConnection error:', error.message)
    return res.fail({ msg: 'mobile ssh connection failed' })
  }
}

module.exports = {
  getMobileSshConnection,
  getMobileConnectionTopology,
  normalizePort,
  normalizeMobileAuthPayload,
  normalizeMobileProxy,
  toMobileSshPayload
}
