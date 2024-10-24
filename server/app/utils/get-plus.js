const schedule = require('node-schedule')
const { getLocalNetIP } = require('./tools')
const { AESEncryptAsync } = require('./encrypt')
const version = require('../../package.json').version

async function getLicenseInfo() {
  let key = process.env.PLUS_KEY
  if (!key || typeof key !== 'string' || key.length < 20) return
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
    return
  }
  try {
    let response
    let method = 'POST'
    let body = JSON.stringify({ ip, key, version })
    let headers = { 'Content-Type': 'application/json' }
    let timeout = 10000
    try {
      response = await fetch('https://en1.221022.xyz/api/licenses/activate', {
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
      response = await fetch('https://en2.221022.xyz/api/licenses/activate', {
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
      const { PlusDB } = require('./db-class')
      const plusData = { key, decryptKey, expiryDate, usedIPCount, maxIPs, usedIPs }
      const plusDB = new PlusDB().getInstance()
      let count = await plusDB.countAsync({})
      if (count === 0) {
        await plusDB.insertAsync(plusData)
      } else {
        await plusDB.removeAsync({}, { multi: true })
        await plusDB.insertAsync(plusData)
      }
    }
  } catch (error) {
    consola.error(`activate plus failed: ${ error.message || error.errMsg?.message }`)
    if (error.clear) {
      const { PlusDB } = require('./db-class')
      const plusDB = new PlusDB().getInstance()
      await plusDB.removeAsync({}, { multi: true })
    }
  }
}

const randomHour = Math.floor(Math.random() * 24)
const randomMinute = Math.floor(Math.random() * 60)
const randomDay = Math.floor(Math.random() * 7)
const cronExpression = `${ randomMinute } ${ randomHour } * * ${ randomDay }`
schedule.scheduleJob(cronExpression, getLicenseInfo)

module.exports = getLicenseInfo
