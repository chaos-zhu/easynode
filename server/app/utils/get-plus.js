const crypto = require('crypto')
const { getLocalNetIP, requestWithFailover } = require('./tools')
const { AESEncryptAsync } = require('./encrypt')
const version = require('../../package.json').version
const { PlusDB } = require('./db-class')
const { RuntimeState } = require('./runtime-state')
const plusDB = new PlusDB().getInstance()
const runtimeState = new RuntimeState().getInstance()

const RETRY_INTERVAL_MS = 30 * 1000
let retryTimer = null

async function getLicenseInfo(key = '') {
  const existing = (await plusDB.findOneAsync({})) || {}
  const { key: plusKey, deviceId: existingDeviceId } = existing
  key = key || plusKey || process.env.PLUS_KEY
  if (!key || key.length < 16) return { success: false, msg: 'Invalid Plus Key', terminated: true }
  try {
    const requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, version })
    }

    const response = await requestWithFailover('/api/licenses/activate', requestOptions)

    if (!response.ok) {
      logger.info('😒激活PLUS功能失败: ', response.status)
      if (response.status === 403) {
        const errMsg = await response.json()
        throw { errMsg, clear: true }
      }
      throw Error({ errMsg: `HTTP error! status: ${ response.status }` })
    }

    const { success, data } = await response.json()
    if (success) {
      let { decryptKey, expiryDate, usedIPCount, maxIPs, usedIPs } = data
      const decryptKeyCipher = await AESEncryptAsync(decryptKey)
      runtimeState.setDecryptKey(decryptKeyCipher)
      const deviceId = existingDeviceId || crypto.randomUUID()
      logger.info('🎉PLUS功能激活成功')
      const plusData = { key, deviceId, expiryDate, usedIPCount, maxIPs, usedIPs }
      const count = await plusDB.countAsync({})
      if (count === 0) {
        await plusDB.insertAsync(plusData)
      } else {
        await plusDB.removeAsync({}, { multi: true })
        await plusDB.insertAsync(plusData)
      }
      return { success: true, msg: '激活成功' }
    }
    logger.error('😒激活PLUS功能失败: ', data)
    return { success: false, msg: '激活失败', terminated: true }
  } catch (error) {
    logger.error(`😒激活PLUS功能失败: ${ error.message || error.errMsg?.message }`)
    if (error.clear) {
      await plusDB.removeAsync({}, { multi: true })
      runtimeState.clearDecryptKey()
      return { success: false, msg: error.errMsg?.message || error.message, terminated: true }
    }
    return { success: false, msg: error.message || error.errMsg?.message }
  }
}

function scheduleNextActivation() {
  if (retryTimer) return
  retryTimer = setTimeout(async () => {
    retryTimer = null
    const result = await getLicenseInfo()
    if (!result.success && !result.terminated) {
      scheduleNextActivation()
    }
  }, RETRY_INTERVAL_MS)
  if (retryTimer.unref) retryTimer.unref()
}

async function purgeLegacyDecryptKey() {
  const existing = await plusDB.findOneAsync({})
  if (existing && Object.prototype.hasOwnProperty.call(existing, 'decryptKey')) {
    await plusDB.updateAsync({}, { $unset: { decryptKey: true } }, { multi: true })
    logger.info('已清理 plusDB 中的遗留 decryptKey 字段')
  }
}

async function startActivation() {
  await purgeLegacyDecryptKey()
  const result = await getLicenseInfo()
  if (!result.success && !result.terminated) {
    scheduleNextActivation()
  }
  return result
}

module.exports = getLicenseInfo
module.exports.startActivation = startActivation
