import jwt from 'jsonwebtoken'
import { AESDecryptAsync } from './encrypt.js'
import { isAllowedIp, getClientIP } from '../utils/tools.js'
import { SHA256Encrypt } from '../utils/encrypt.js'
import { KeyDB, SessionDB } from './db-class.js'
const keyDB = new KeyDB().getInstance()
const sessionDB = new SessionDB().getInstance()

const enumLoginCode = {
  SUCCESS: 'SUCCESS',
  EXPIRES: 'TOKEN_EXPIRES',
  ERROR_TOKEN: 'TOKEN_ERROR',
  ERROR_UID: 'USER_ID_ERROR',
  REVOKED_TOKEN: 'REVOKED_TOKEN',
  SID_EXPIRES: 'SID_EXPIRES'
}

// 解析 Cookie
const parseCookies = (cookieString) => {
  if (!cookieString) return {}
  return Object.fromEntries(
    cookieString.split(';').map(c => {
      const [key, ...v] = c.trim().split('=')
      return [key, decodeURIComponent(v.join('='))]
    })
  )
}

// 校验token&session
const verifyAuthSync = async (token, session) => {
  try {
    const { jwtToken, _id: userId } = await keyDB.findOneAsync({})
    token = await AESDecryptAsync(token)
    jwt.verify(token, `${ jwtToken }-${ userId }`)
    const sessionRecord = await sessionDB.findOneAsync({ session })
    // 是否无效/注销/过期的token
    if (!session || !sessionRecord || sessionRecord.revoked !== false) {
      return { code: enumLoginCode.REVOKED_TOKEN, success: false }
    }
    // session是否过期
    if (sessionRecord.expireAt < Date.now()) {
      await sessionDB.updateAsync({ session }, { $set: { revoked: true } }) // 标记为已撤销
      return { code: enumLoginCode.SID_EXPIRES, success: false } //sid过期
    }
    // 验证token是否匹配session
    const currentTokenHash = SHA256Encrypt(token)
    if (sessionRecord.tokenHash !== currentTokenHash) {
      logger.warn('⚠: Token 哈希不匹配，可能的安全威胁')
      return { code: enumLoginCode.ERROR_TOKEN, success: false }
    }

    return { code: enumLoginCode.SUCCESS, success: true } // 验证成功
  } catch (err) {
    if (err.name === 'TokenExpiredError') return { code: enumLoginCode.EXPIRES, success: false }
    logger.error('用户身份校验失败: ', err.message)
    return { code: enumLoginCode.ERROR_TOKEN, success: false }
  }
}

const verifyWsAuthSync = async (socket, next) => {
  const requestIP = getClientIP(socket.conn.remoteAddress, socket.handshake.headers['x-forwarded-for'])
  // console.log('ws terminal requestIP:', requestIP)
  // IP 白名单检查
  if (!isAllowedIp(requestIP)) {
    logger.warn('ws终端连接IP不在白名单中: ', requestIP)
    return next(new Error('IP not allowed')) // ✅ 使用 next(error)
  }
  // Cookie 检查
  const cookies = socket.handshake.headers.cookie
  if (!cookies) {
    logger.warn('终端连接缺少 Cookie')
    return next(new Error('No Cookie'))
  }
  // Session 检查
  const { session } = parseCookies(cookies)
  // console.log('ws terminal session:', session)
  if (!session) {
    logger.warn('终端连接缺少 Session Cookie')
    return next(new Error('No Session Cookie'))
  }
  // Token 检查
  const { token } = socket.handshake.auth || {}
  // console.log('ws terminal token:', token)
  if (!token) {
    logger.warn('终端连接缺少 Token')
    return next(new Error('No Token'))
  }
  // 验证身份
  const { success, code } = await verifyAuthSync(token, session)
  if (!success) {
    logger.warn('ws终端连接身份验证失败, code:', code)
    return next(new Error('Authentication Failed'))
  }
  // console.log('🤓 ws terminal auth success')
  next()
}

export {
  enumLoginCode,
  verifyAuthSync,
  verifyWsAuthSync,
  parseCookies
}
