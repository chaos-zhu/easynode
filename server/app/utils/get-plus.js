const { getLocalNetIP } = require('./tools')
const { AESEncryptAsync } = require('./encrypt')
const version = require('../../package.json').version
const { plusServer1, plusServer2 } = require('./plus-server')
const { PlusDB } = require('./db-class')
const plusDB = new PlusDB().getInstance()

async function getLicenseInfo(key = '') {
  const { key: plusKey } = await plusDB.findOneAsync({}) || {}
  // console.log('plusKey: ', plusKey)
  // console.log('key: ', key)
  // console.log('process.env.PLUS_KEY: ', process.env.PLUS_KEY)
  key = key || plusKey || process.env.PLUS_KEY
  if (!key || key.length < 16) return { success: false, msg: 'Invalid Plus Key' }
  let ip = ''
  if (global.serverIp && (Date.now() - global.getServerIpLastTime) / 1000 / 60 < 60) {
    ip = global.serverIp
    consola.log('get server ip by cache: ', ip)
  } else {
    ip = await getLocalNetIP()
    global.serverIp = ip
    global.getServerIpLastTime = Date.now()
    consola.log('get server ip by net: ', ip)
  }
  if (!ip) {
    consola.error('activate plus failed: get public ip failed')
    global.serverIp = ''
    return { success: false, msg: 'get public ip failed' }
  }
  try {
    let response
    let method = 'POST'
    let body = JSON.stringify({ ip, key, version })
    let headers = { 'Content-Type': 'application/json' }
    let timeout = 10000
    try {
      response = await fetch(plusServer1 + '/api/licenses/activate', {
        method,
        headers,
        body,
        timeout
      })

      if (!response.ok && (response.status !== 403)) {
        throw new Error('port1 error')
      }

    } catch (error) {
      consola.log('retry to activate plus by backup server')
      response = await fetch(plusServer2 + '/api/licenses/activate', {
        method,
        headers,
        body,
        timeout
      })
    }

    if (!response.ok) {
      consola.log('activate plus failed: ', response.status)
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
      consola.success('activate plus success')
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
    consola.error('activate plus failed: ', data)
    return { success: false, msg: '激活失败' }
  } catch (error) {
    consola.error(`activate plus failed: ${ error.message || error.errMsg?.message }`)
    if (error.clear) {
      await plusDB.removeAsync({}, { multi: true })
    }
    return { success: false, msg: error.message || error.errMsg?.message }
  }
}

module.exports = getLicenseInfo
