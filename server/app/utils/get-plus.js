const { getLocalNetIP, requestWithFailover } = require('./tools')
const { AESEncryptAsync } = require('./encrypt')
const version = require('../../package.json').version
const { PlusDB } = require('./db-class')
const plusDB = new PlusDB().getInstance()

async function getLicenseInfo(key = '') {
  const { key: plusKey } = await plusDB.findOneAsync({}) || {}
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
      decryptKey = await AESEncryptAsync(decryptKey)
      logger.info('🎉PLUS功能激活成功')
      const plusData = { key, decryptKey, expiryDate, usedIPCount, maxIPs, usedIPs }
      let count = await plusDB.countAsync({})
      if (count === 0) {
        await plusDB.insertAsync(plusData)
      } else {
        await plusDB.removeAsync({}, { multi: true })
        await plusDB.insertAsync(plusData)
      }
      return { success: true, msg: '激活成功' }
    }
    logger.error('😒激活PLUS功能失败: ', data)
    return { success: false, msg: '激活失败' }
  } catch (error) {
    logger.error(`😒激活PLUS功能失败: ${ error.message || error.errMsg?.message }`)
    if (error.clear) {
      await plusDB.removeAsync({}, { multi: true })
    }
    return { success: false, msg: error.message || error.errMsg?.message }
  }
}

module.exports = getLicenseInfo
