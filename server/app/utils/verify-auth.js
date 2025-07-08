
const { AESDecryptAsync } = require('./encrypt')
const jwt = require('jsonwebtoken')
const { KeyDB } = require('./db-class')
const keyDB = new KeyDB().getInstance()

const enumLoginCode = {
  SUCCESS: 1,
  EXPIRES: -1,
  ERROR_TOKEN: -2
}

// 校验token
const verifyAuthSync = async (token, clientIp) => {
  // consola.info('verifyAuthSync IP：', clientIp)
  try {
    token = await AESDecryptAsync(token) // 先aes解密
    const { commonKey } = await keyDB.findOneAsync({})
    const { exp } = jwt.verify(token, commonKey)
    if (Date.now() > (exp * 1000)) return { code: -1, msg: 'token expires' } // 过期
    return { code: enumLoginCode.SUCCESS, msg: 'success' } // 验证成功
  } catch (error) {
    return { code: enumLoginCode.ERROR_TOKEN, msg: error } // token错误, 验证失败
  }
}

module.exports = {
  verifyAuthSync
}