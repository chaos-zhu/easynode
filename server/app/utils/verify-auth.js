
const { AESDecryptAsync } = require('./encrypt')
const jwt = require('jsonwebtoken')
const { KeyDB } = require('./db-class')
const keyDB = new KeyDB().getInstance()

const enumLoginCode = {
  SUCCESS: 'SUCCESS',
  EXPIRES: 'TOKEN_EXPIRES',
  ERROR_TOKEN: 'TOKEN_ERROR',
  ERROR_UID: 'USER_ID_ERROR'
}

// 校验token&uid
const verifyAuthSync = async (token, userId) => {
  try {
    const { commonKey, user, _id: uid } = await keyDB.findOneAsync({ _id: userId })
    if (uid !== userId) return { code: enumLoginCode.ERROR_UID, msg: '用户id校验失败' }
    token = await AESDecryptAsync(token)
    const { exp } = jwt.verify(token, `${ user }-${ commonKey }`)
    if (Date.now() > (exp * 1000)) {
      return { code: enumLoginCode.EXPIRES } // 过期
    }
    return { code: enumLoginCode.SUCCESS } // 验证成功
  } catch (err) {
    consola.error('用户身份校验失败: ', err.message)
    return { code: enumLoginCode.ERROR_TOKEN }
  }
}

module.exports = {
  verifyAuthSync,
  enumLoginCode
}