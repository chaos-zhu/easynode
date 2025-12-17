
const { AESDecryptAsync } = require('./encrypt')
const jwt = require('jsonwebtoken')
const { KeyDB, SessionDB } = require('./db-class')
const keyDB = new KeyDB().getInstance()
const sessionDB = new SessionDB().getInstance()

const enumLoginCode = {
  SUCCESS: 'SUCCESS',
  EXPIRES: 'TOKEN_EXPIRES',
  ERROR_TOKEN: 'TOKEN_ERROR',
  ERROR_UID: 'USER_ID_ERROR',
  REVOKED_TOKEN: 'REVOKED_TOKEN'
}

// 校验token&uid
const verifyAuthSync = async (token, userId) => {
  try {
    const { jwtToken, user, _id: uid } = await keyDB.findOneAsync({ _id: userId })
    if (uid !== userId) return { code: enumLoginCode.ERROR_UID }
    token = await AESDecryptAsync(token)
    const payload = jwt.verify(token, `${ jwtToken }-${ user }`)
    const { sid } = payload
    const sessionRecord = await sessionDB.findOneAsync({ sid })
    if (!sessionRecord || sessionRecord.revoked) {
      return { code: enumLoginCode.REVOKED_TOKEN, success: false } // 被注销的token
    }
    return { code: enumLoginCode.SUCCESS, success: true } // 验证成功
  } catch (err) {
    if (err.name === 'TokenExpiredError') return { code: enumLoginCode.EXPIRES }
    logger.error('用户身份校验失败: ', err.message)
    return { code: enumLoginCode.ERROR_TOKEN }
  }
}

module.exports = {
  verifyAuthSync,
  enumLoginCode
}