
const { AESDecrypt } = require('./encrypt')
const { readKey } = require('./storage')
const jwt = require('jsonwebtoken')

const enumLoginCode = {
  SUCCESS: 1,
  EXPIRES: -1,
  ERROR_TOKEN: -2
}

// 校验token与登录IP
const verifyAuth = (token, clientIp) =>{
  if(['::ffff:', '::1'].includes(clientIp)) clientIp = '127.0.0.1'
  token = AESDecrypt(token) // 先aes解密
  const { commonKey } = readKey()
  try {
    const { exp } = jwt.verify(token, commonKey)
    if(Date.now() > (exp * 1000)) return { code: -1, msg: 'token expires' } // 过期

    let lastLoginIp = global.loginRecord[0] ? global.loginRecord[0].ip : ''
    consola.info('校验客户端IP：', clientIp)
    consola.info('最后登录的IP：', lastLoginIp)
    // 判断: (生产环境)clientIp与上次登录成功IP不一致
    if(isProd() && (!lastLoginIp || !clientIp || !clientIp.includes(lastLoginIp))) {
      return { code: enumLoginCode.EXPIRES, msg: '登录IP发生变化, 需重新登录' } // IP与上次登录访问的不一致
    }
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
  verifyAuth,
  isProd
}