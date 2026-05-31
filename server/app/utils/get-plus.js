const crypto = require('crypto')
const path = require('path')
const { requestWithFailover } = require('./tools')
const { AESEncryptAsync } = require('./encrypt')
const decryptAndExecuteAsync = require('./decrypt-file')
const version = require('../../package.json').version
const { PlusDB } = require('./db-class')
const { RuntimeState } = require('./runtime-state')
const plusDB = new PlusDB().getInstance()
const runtimeState = new RuntimeState().getInstance()

const RETRY_INTERVAL_MS = 30 * 1000
let maxRetryCount = 3
let retryTimer = null

async function startHeartbeatIfAvailable() {
  const plusModule = await decryptAndExecuteAsync(path.join(__dirname, '../controller/plus.js'))
  if (typeof plusModule?.startHeartbeat === 'function') {
    plusModule.startHeartbeat()
  } else {
    logger.info('[Plus] Heartbeat module is not available')
  }
}

async function getLicenseInfo(key = '') {
  const existing = (await plusDB.findOneAsync({})) || {}
  const { key: plusKey, deviceId: existingDeviceId } = existing
  key = key || plusKey || process.env.PLUS_KEY
  if (!key || key.length < 16) return { success: false, msg: 'Invalid Plus Key' }
  try {
    const requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, version })
    }

    const response = await requestWithFailover('/api/licenses/activate', requestOptions)

    if (!response.ok) {
      if (response.status === 403) {
        const errMsg = await response.json()
        throw { errMsg: `403: ${ errMsg?.message }`, clear: true }
      }
      throw Error({ errMsg: `HTTP error! status: ${ response.status }` })
    }

    const { success, data } = await response.json()
    if (success) {
      let { decryptKey } = data
      const decryptKeyCipher = await AESEncryptAsync(decryptKey)
      runtimeState.setDecryptKey(decryptKeyCipher)
      const deviceId = existingDeviceId || crypto.randomUUID()
      logger.info('🎉PLUS功能激活成功')
      const plusData = { key, deviceId }
      const count = await plusDB.countAsync({})
      if (count === 0) {
        await plusDB.insertAsync(plusData)
      } else {
        await plusDB.removeAsync({}, { multi: true })
        await plusDB.insertAsync(plusData)
      }
      await startHeartbeatIfAvailable()
      return { success: true, msg: '激活成功' }
    }
    logger.error('😒激活PLUS功能失败: ', data)
    return { success: false, msg: '激活失败' }
  } catch (error) {
    logger.error(`😒激活PLUS功能失败: ${ error?.errMsg || error?.message || error }`)
    if (error.clear) {
      await plusDB.removeAsync({}, { multi: true })
      runtimeState.clearDecryptKey()
    }
    return { success: false, msg: error?.errMsg || error?.message || error, clear: error.clear }
  }
}

async function activateOrRetry() {
  const { key: plusKey } = (await plusDB.findOneAsync({})) || {}
  if (!plusKey && !process.env.PLUS_KEY) return
  const result = await getLicenseInfo()
  if (result.clear) return logger.error('[Plus] Plus key has been cleared due to activation issues')
  if (!result.success) scheduleNextActivation()
}

function scheduleNextActivation() {
  maxRetryCount--
  if (retryTimer || maxRetryCount <= 0) return
  retryTimer = setTimeout(() => {
    retryTimer = null
    activateOrRetry()
  }, RETRY_INTERVAL_MS)
  if (retryTimer.unref) retryTimer.unref()
}

module.exports = getLicenseInfo
module.exports.startActivation = activateOrRetry
