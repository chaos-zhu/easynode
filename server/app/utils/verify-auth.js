
const { AESDecryptSync } = require('./encrypt')
const { readKey } = require('./storage')
const jwt = require('jsonwebtoken')

const enumLoginCode = {
  SUCCESS: 1,
  EXPIRES: -1,
  ERROR_TOKEN: -2
}

// 校验token与登录IP
const verifyAuthSync = async (token, clientIp) => {
  consola.info('verifyAuthSync IP：', clientIp)
  try {
    token = await AESDecryptSync(token) // 先aes解密
    const { commonKey } = await readKey()
    const { exp } = jwt.verify(token, commonKey)
    if (Date.now() > (exp * 1000)) return { code: -1, msg: 'token expires' } // 过期
    return { code: enumLoginCode.SUCCESS, msg: 'success' } // 验证成功
  } catch (error) {
    return { code: enumLoginCode.ERROR_TOKEN, msg: error } // token错误, 验证失败
  }
}

const isProd = () => {
  const EXEC_ENV = process.env.EXEC_ENV || 'production'
  return EXEC_ENV === 'production'
}

module.exports = {
  verifyAuthSync,
  isProd
}