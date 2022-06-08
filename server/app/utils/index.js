const fs = require('fs')
const jwt = require('jsonwebtoken')
const axios = require('axios')
const NodeRSA = require('node-rsa')

const { sshRecordPath, hostListPath, keyPath } = require('../config')

const readSSHRecord = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(sshRecordPath, 'utf8'))
  } catch (error) {
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

const getLocalNetIP = async () => {
  try {
    let ipUrls = ['http://ip-api.com/json/?lang=zh-CN', 'http://whois.pconline.com.cn/ipJson.jsp?json=true']
    let { data } = await Promise.race(ipUrls.map(url => axios.get(url)))
    return data.ip || data.query
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
  err.status = status
  throw err
}

const isIP = (ip = '') => {
  const isIPv4 = /^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$/
  const isIPv6 = /^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}|:((:[\da−fA−F]1,4)1,6|:)|:((:[\da−fA−F]1,4)1,6|:)|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?|([\da−fA−F]1,4:)6:|([\da−fA−F]1,4:)6:/
  return isIPv4.test(ip) || isIPv6.test(ip)
}

const randomStr = (e) =>{
  e = e || 32
  let str = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678',
    a = str.length,
    res = ''
  for (let i = 0; i < e; i++) res += str.charAt(Math.floor(Math.random() * a))
  return res
}

const verifyToken = (token) =>{
  const { jwtSecret } = readKey()
  try {
    const { exp } = jwt.verify(token, jwtSecret)
    if(Date.now() > (exp * 1000)) return { code: -1, msg: 'token expires' }
    return { code: 1, msg: 'success' }
  } catch (error) {
    return { code: -2, msg: error }
  }
}

const isProd = () => {
  const EXEC_ENV = process.env.EXEC_ENV || 'production'
  return EXEC_ENV === 'production'
}

const decrypt = (ciphertext) => {
  let { privateKey } = readKey()
  const rsakey = new NodeRSA(privateKey)
  rsakey.setOptions({ encryptionScheme: 'pkcs1' })
  const plaintext = rsakey.decrypt(ciphertext, 'utf8')
  return plaintext
}

module.exports = {
  readSSHRecord,
  writeSSHRecord,
  readHostList,
  writeHostList,
  getLocalNetIP,
  throwError,
  isIP,
  readKey,
  writeKey,
  randomStr,
  verifyToken,
  isProd,
  decrypt
}