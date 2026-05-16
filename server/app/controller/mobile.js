const { RSADecryptAsync } = require('../utils/encrypt')
const { encryptJsonForMobile } = require('../utils/mobile-crypto')

function toMobileSshPayload(hostId, name, authInfo) {
  const { host, port, username, authType } = authInfo
  if (!['password', 'privateKey'].includes(authType)) {
    throw new Error(`unsupported mobile ssh auth type: ${ authType || 'empty' }`)
  }

  return {
    hostId,
    name,
    host,
    port: Number(port || 22),
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
      return res.fail({ msg: 'missing params: hostId or encryptedKey' })
    }

    const tempKeyText = await RSADecryptAsync(encryptedKey)
    const tempKey = Buffer.from(tempKeyText, 'base64')
    const { getConnectionOptions } = require('../socket/terminal')
    const { authInfo, name } = await getConnectionOptions(hostId)
    const payload = toMobileSshPayload(hostId, name, authInfo)
    const data = encryptJsonForMobile(payload, tempKey)

    return res.success({ data, msg: 'success' })
  } catch (error) {
    logger.error('getMobileSshConnection error:', error.message)
    return res.fail({ msg: error.message || 'mobile ssh connection failed' })
  }
}

module.exports = {
  getMobileSshConnection,
  toMobileSshPayload
}
