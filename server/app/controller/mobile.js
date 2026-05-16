const { RSADecryptAsync } = require('../utils/encrypt')
const { encryptJsonForMobile } = require('../utils/mobile-crypto')
const { getConnectionOptions } = require('../socket/terminal')

function toMobileSshPayload(hostId, name, authInfo) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported mobile ssh auth type: ${ authType || 'empty' }`)
  }

  const numericPort = Number(port)
  return {
    hostId,
    name,
    host,
    port: Number.isFinite(numericPort) && numericPort > 0 ? numericPort : 22,
    username,
    authType,
    password: authType === 'password' ? authInfo.password || '' : '',
    privateKey: authType === 'privateKey' ? authInfo.privateKey || '' : '',
    passphrase: authType === 'privateKey' ? authInfo.passphrase || '' : ''
  }
}

async function getMobileSshConnection({ request, res }) {
  try {
    const { hostId, encryptedKey } = request.body || {}
    if (!hostId || !encryptedKey) {
      return res.fail({ msg: 'missing params' })
    }

    const tempKeyText = await RSADecryptAsync(encryptedKey)
    const tempKey = Buffer.from(tempKeyText, 'base64')
    const { authInfo, name } = await getConnectionOptions(hostId)
    const payload = toMobileSshPayload(hostId, name, authInfo)
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
  toMobileSshPayload
}
