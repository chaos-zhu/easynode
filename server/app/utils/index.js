const fs = require('fs')
const CryptoJS = require('crypto-js')
const rawCrypto = require('crypto')
const NodeRSA = require('node-rsa')
const jwt = require('jsonwebtoken')
const axios = require('axios')
const request = axios.create({ timeout: 3000 })

const { sshRecordPath, hostListPath, keyPath } = require('../config')

const readSSHRecord = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(sshRecordPath, 'utf8'))
  } catch (error) {
    console.log('读取ssh-record错误, 即将重置ssh列表: ', error)
    writeSSHRecord([])
  }
  return list || []
}

const writeSSHRecord = (record = []) => {
  fs.writeFileSync(sshRecordPath, JSON.stringify(record, null, 2))
}

const readHostList = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(hostListPath, 'utf8'))
  } catch (error) {
    console.log('读取host-list错误, 即将重置host列表: ', error)
    writeHostList([])
  }
  return list || []
}

const writeHostList = (record = []) => {
  fs.writeFileSync(hostListPath, JSON.stringify(record, null, 2))
}

const readKey = () => {
  let keyObj = JSON.parse(fs.readFileSync(keyPath, 'utf8'))
  return keyObj
}

const writeKey = (keyObj = {}) => {
  fs.writeFileSync(keyPath, JSON.stringify(keyObj, null, 2))
}

// 为空时请求本地IP
const getNetIPInfo = async (ip = '') => {
  try {
    let date = getUTCDate(8)
    let ipUrls = [`http://ip-api.com/json/${ ip }?lang=zh-CN`, `http://whois.pconline.com.cn/ipJson.jsp?json=true&ip=${ ip }`]
    let result = await Promise.allSettled(ipUrls.map(url => request.get(url)))
    let [ipApi, pconline] = result
    if(ipApi.status === 'fulfilled') {
      let { query: ip, country, regionName, city } = ipApi.value.data
      // console.log({ ip, country, city: regionName + city })
      return { ip, country, city: regionName + city, date }
    }
    if(pconline.status === 'fulfilled') {
      let { ip, pro, city, addr } = pconline.value.data
      // console.log({ ip, country: pro || addr, city })
      return { ip, country: pro || addr, city, date }
    }
    throw Error('获取IP信息API出错,请排查或更新API')
  } catch (error) {
    console.error('getIpInfo Error: ', error)
    return {
      ip: '未知',
      country: '未知',
      city: '未知',
      error
    }
  }
}

const throwError = ({ status = 500, msg = 'defalut error' } = {}) => {
  const err = new Error(msg)
  err.status = status // 主动抛错
  throw err
}

const isIP = (ip = '') => {
  const isIPv4 = /^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$/
  const isIPv6 = /^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}|:((:[\da−fA−F]1,4)1,6|:)|:((:[\da−fA−F]1,4)1,6|:)|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?|([\da−fA−F]1,4:)6:|([\da−fA−F]1,4:)6:/
  return isIPv4.test(ip) || isIPv6.test(ip)
}

const randomStr = (e) =>{
  e = e || 16
  let str = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678',
    a = str.length,
    res = ''
  for (let i = 0; i < e; i++) res += str.charAt(Math.floor(Math.random() * a))
  return res
}

// 校验token与登录IP
const verifyAuth = (token, clientIp) =>{
  token = AESDecrypt(token) // 先aes解密
  const { commonKey } = readKey()
  try {
    const { exp } = jwt.verify(token, commonKey)
    // console.log('校验token：', new Date(), '---', new Date(exp * 1000))
    if(Date.now() > (exp * 1000)) return { code: -1, msg: 'token expires' } // 过期

    let lastLoginIp = global.loginRecord[0] ? global.loginRecord[0].ip : ''
    console.log('校验客户端IP：', clientIp)
    console.log('最后登录的IP：', lastLoginIp)
    // 判断: (生产环境)clientIp与上次登录成功IP不一致
    if(isProd() && (!lastLoginIp || !clientIp || !clientIp.includes(lastLoginIp))) {
      return { code: -1, msg: '登录IP发生变化, 需重新登录' } // IP与上次登录访问的不一致
    }
    // console.log('token验证成功')
    return { code: 1, msg: 'success' } // 验证成功
  } catch (error) {
    // console.log('token校验错误：', error)
    return { code: -2, msg: error } // token错误, 验证失败
  }
}

const isProd = () => {
  const EXEC_ENV = process.env.EXEC_ENV || 'production'
  return EXEC_ENV === 'production'
}

// rsa非对称 私钥解密
const RSADecrypt = (ciphertext) => {
  if(!ciphertext) return
  let { privateKey } = readKey()
  privateKey = AESDecrypt(privateKey) // 先解密私钥
  const rsakey = new NodeRSA(privateKey)
  rsakey.setOptions({ encryptionScheme: 'pkcs1' }) // Must Set It When Frontend Use jsencrypt
  const plaintext = rsakey.decrypt(ciphertext, 'utf8')
  return plaintext
}

// aes对称 加密(default commonKey)
const AESEncrypt = (text, key) => {
  if(!text) return
  let { commonKey } = readKey()
  let ciphertext = CryptoJS.AES.encrypt(text, key || commonKey).toString()
  return ciphertext
}

// aes对称 解密(default commonKey)
const AESDecrypt = (ciphertext, key) => {
  if(!ciphertext) return
  let { commonKey } = readKey()
  let bytes = CryptoJS.AES.decrypt(ciphertext, key || commonKey)
  let originalText = bytes.toString(CryptoJS.enc.Utf8)
  return originalText
}

// sha1 加密(不可逆)
const SHA1Encrypt = (clearText) => {
  return rawCrypto.createHash('sha1').update(clearText).digest('hex')
}

// 获取UTC-x时间
const getUTCDate = (num = 8) => {
  let date = new Date()
  let now_utc = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(),
    date.getUTCDate(), date.getUTCHours() + num,
    date.getUTCMinutes(), date.getUTCSeconds())
  return new Date(now_utc)
}

module.exports = {
  readSSHRecord,
  writeSSHRecord,
  readHostList,
  writeHostList,
  getNetIPInfo,
  throwError,
  isIP,
  readKey,
  writeKey,
  randomStr,
  verifyAuth,
  isProd,
  RSADecrypt,
  AESEncrypt,
  AESDecrypt,
  SHA1Encrypt,
  getUTCDate
}