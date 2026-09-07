import jwt from 'jsonwebtoken'
import axios from 'axios'
import speakeasy from 'speakeasy'
import QRCode from 'qrcode'
import { UAParser as uap } from 'ua-parser-js'
import { v4 as uuidv4 } from 'uuid'
import PackageJsonModule from '../../package.json' with { type: 'json' }
const version = PackageJsonModule.version
import getLicenseInfo from '../utils/get-plus.js'
import { sendNoticeAsync } from '../utils/notify.js'
import { InvalidCiphertextError, RSADecryptAsync, AESEncryptAsync, SHA1Encrypt, SHA256Encrypt } from '../utils/encrypt.js'
import { getClientIP, getNetIPInfo, randomStr, requestWithFailover, timingSafeEqual } from '../utils/tools.js'
import { KeyDB, PlusDB, SessionDB } from '../utils/db-class.js'
import { RuntimeState } from '../utils/runtime-state.js'
import { DEFAULT_LOCK_DURATION_MS, DEFAULT_MAX_ATTEMPTS, loginAttemptLimiter } from '../utils/login-attempt-limiter.js'
import { cookieSecure } from '../config/index.js'
import { disconnectAllSessionConnections, revokeAllSessions } from '../utils/auth-session.js'

const keyDB = new KeyDB().getInstance()
const sessionDB = new SessionDB().getInstance()
const plusDB = new PlusDB().getInstance()
const runtimeState = new RuntimeState().getInstance()

// 仅允许三种登录有效期：3天 / 7天 / 30天
const ALLOWED_JWT_EXPIRES = {
  '3d': 3 * 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000
}

const getpublicKey = async ({ res }) => {
  let { publicKey: data } = await keyDB.findOneAsync({})
  if (!data) return res.fail({ msg: 'publicKey not found, Try to restart the server', status: 500 })
  res.success({ data })
}

const parseLoginAgentInfo = (userAgent = '') => {
  const nativeMatch = userAgent.match(/^EasyNode-(Android|iOS|macOS|Windows|Linux|Native)\/(\S+)\s*(?:\(([^)]*)\))?/)
  if (nativeMatch) {
    const [, clientName, appVersion, parenContent = ''] = nativeMatch
    const parts = parenContent.split(';').map(s => s.trim()).filter(Boolean)
    return {
      browser: { name: `EasyNode ${ clientName }`, version: appVersion || '' },
      os: { name: clientName, version: parts.join('; ') || '' }
    }
  }
  return uap(userAgent)
}

const respondLoginLocked = (ctx, lockStatus) => {
  const { res } = ctx
  const retryAfterSeconds = lockStatus.retryAfterSeconds
  ctx.set('Retry-After', String(retryAfterSeconds))
  return res.fail({
    status: 429,
    data: { retryAfterSeconds },
    msg: `登录失败次数过多，请在 ${ retryAfterSeconds } 秒后重试`
  })
}

const notifyLoginLocked = async (clientIp) => {
  // 异步查询IP归属地，不阻塞锁定响应
  getNetIPInfo(clientIp).then(({ country = '未知', city = '未知' } = {}) => {
    sendNoticeAsync(
      'err_login',
      '登录错误提醒',
      `错误登录次数: ${ DEFAULT_MAX_ATTEMPTS }\n地点：${ country }${ city }\nIP: ${ clientIp }\n锁定时间: ${ DEFAULT_LOCK_DURATION_MS / 60_000 }分钟`
    )
  }).catch(error => {
    logger.error('查询登录锁定IP归属地失败:', error)
    // 即使IP查询失败也发送通知
    sendNoticeAsync(
      'err_login',
      '登录错误提醒',
      `错误登录次数: ${ DEFAULT_MAX_ATTEMPTS }\n地点：未知\nIP: ${ clientIp }\n锁定时间: ${ DEFAULT_LOCK_DURATION_MS / 60_000 }分钟`
    )
  })
}

const failLoginAttempt = (ctx, clientIp, msg) => {
  const lockStatus = loginAttemptLimiter.recordFailure(clientIp)
  if (lockStatus.locked) {
    if (lockStatus.justLocked) {
      notifyLoginLocked(clientIp).catch(error => logger.error('发送登录锁定通知失败:', error.message))
    }
    return respondLoginLocked(ctx, lockStatus)
  }
  return ctx.res.fail({
    status: 400,
    msg: `${ msg } ${ lockStatus.failedAttempts }/${ DEFAULT_MAX_ATTEMPTS }`
  })
}

const login = async (ctx) => {
  const { res, request } = ctx
  const clientIp = getClientIP(ctx.socket?.remoteAddress, ctx.get('x-forwarded-for')) || 'unknown'
  const lockStatus = loginAttemptLimiter.getStatus(clientIp)
  if (lockStatus.locked) return respondLoginLocked(ctx, lockStatus)

  const body = request.body
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return failLoginAttempt(ctx, clientIp, '请求非法!')
  }

  const { loginName, ciphertext, jwtExpires, mfa2Token } = body
  const { header } = request
  if (
    typeof loginName !== 'string' || !loginName ||
    typeof ciphertext !== 'string' || !ciphertext ||
    typeof jwtExpires !== 'string' || !jwtExpires
  ) {
    return failLoginAttempt(ctx, clientIp, '请求非法!')
  }

  const jwtExpiresDuration = ALLOWED_JWT_EXPIRES[jwtExpires]
  if (typeof jwtExpiresDuration !== 'number') return failLoginAttempt(ctx, clientIp, '请求非法!')
  const jwtExpireAt = Date.now() + jwtExpiresDuration

  let loginPwd
  try {
    loginPwd = await RSADecryptAsync(ciphertext)
  } catch (error) {
    if (error instanceof InvalidCiphertextError) return failLoginAttempt(ctx, clientIp, '请求非法!')
    logger.error('登录密码解密失败:', error)
    return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
  }

  let keyRecord
  try {
    keyRecord = await keyDB.findOneAsync({})
  } catch (error) {
    logger.error('读取登录配置失败:', error)
    return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
  }

  const { user, pwd, enableMFA2, secret, jwtToken, _id: userId } = keyRecord || {}
  if (
    typeof user !== 'string' || typeof pwd !== 'string' ||
    typeof jwtToken !== 'string' || !jwtToken || !userId
  ) {
    logger.error('登录配置缺少用户名、密码或签名密钥')
    return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
  }

  if (enableMFA2) {
    if (typeof secret !== 'string' || !secret) {
      logger.error('MFA2 已启用但缺少密钥')
      return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
    }
    let isValid
    try {
      isValid = speakeasy.totp.verify({ secret, encoding: 'base32', token: String(mfa2Token), window: 1 })
    } catch (error) {
      logger.error('MFA2 验证配置异常:', error)
      return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
    }
    if (!isValid) return failLoginAttempt(ctx, clientIp, 'MFA2验证失败')
  }

  try {
    // 统一使用SHA1加密验证
    loginPwd = SHA1Encrypt(loginPwd)
    const loginNameMatches = timingSafeEqual(loginName, user)
    const passwordMatches = timingSafeEqual(loginPwd, pwd)
    if (!loginNameMatches || !passwordMatches) {
      return failLoginAttempt(ctx, clientIp, '用户名或密码错误')
    }
  } catch {
    return failLoginAttempt(ctx, clientIp, '请求非法!')
  }
  if (loginName !== user || loginPwd !== pwd) {
    failLoginAttempt(ctx, clientIp, '用户名或密码错误')
    return
  }

  try {
    const { token, session, deviceId } = await beforeLoginHandler(
      clientIp,
      jwtExpires,
      jwtExpireAt,
      parseLoginAgentInfo(header?.['user-agent'] || ''),
      { jwtToken, userId }
    )
    loginAttemptLimiter.reset(clientIp)
    ctx.cookies.set('session', session, {
      httpOnly: true,
      expires: new Date(jwtExpireAt),
      sameSite: 'strict',
      secure: cookieSecure
    })
    return res.success({ data: { token, deviceId }, msg: '登录成功' })
  } catch (error) {
    logger.error('登录失败:', error)
    return res.fail({ status: 500, msg: '登录失败, 请查看服务端日志' })
  }
}

const beforeLoginHandler = async (clientIp, jwtExpires, jwtExpireAt, agentInfo, authSnapshot) => {
  const session = uuidv4()
  const deviceId = uuidv4()
  const { jwtToken, userId } = authSnapshot
  let token = jwt.sign({ create: Date.now(), userId, session }, `${ jwtToken }-${ userId }`, { expiresIn: jwtExpires })
  const tokenHash = SHA256Encrypt(token)
  token = await AESEncryptAsync(token) // 对称加密token后再传输给前端

  // 先插入session记录，IP信息使用占位符
  await sessionDB.insertAsync({
    session,
    tokenHash,
    userId,
    deviceId,
    revoked: false,
    ip: clientIp,
    country: '查询中',
    city: '查询中',
    agentInfo,
    create: Date.now(),
    expireAt: jwtExpireAt
  })

  // 异步查询IP归属地并更新数据库（不阻塞登录响应）
  getNetIPInfo(clientIp).then(clientIPInfo => {
    const { ip, country, city } = clientIPInfo || {}
    logger.info('登录成功:', { ip, country, city, agentInfo })

    // 更新session记录中的IP信息
    sessionDB.updateAsync({ session }, { $set: { ip, country, city } }).catch(error => {
      logger.error('更新IP归属地信息失败:', error)
    })

    // 登录通知
    sendNoticeAsync('login', '登录提醒', `地点：${ country + city }\nIP: ${ ip }\n设备信息: ${ agentInfo?.browser?.name } ${ agentInfo?.os?.name }`)
  }).catch(error => {
    logger.error('查询IP归属地失败:', error)
    // 即使查询失败也更新为未知，避免一直显示"查询中"
    sessionDB.updateAsync({ session }, { $set: { country: '未知', city: '未知' } }).catch(e => {
      logger.error('更新IP归属地信息失败:', e)
    })
  })

  return { token, session, deviceId }
}

const updatePwd = async (ctx) => {
  const { res, request } = ctx
  let { body: { oldLoginName, oldPwd, newLoginName, newPwd } } = request
  let rsaOldPwd = await RSADecryptAsync(oldPwd)
  oldPwd = SHA1Encrypt(rsaOldPwd)
  let keyObj = await keyDB.findOneAsync({})
  let { user, pwd } = keyObj
  if (oldLoginName !== user || oldPwd !== pwd) return res.fail({ data: false, msg: '原用户名或密码校验失败' })
  // 旧密钥校验通过，加密保存新密码
  newPwd = SHA1Encrypt(await RSADecryptAsync(newPwd))
  keyObj.user = newLoginName
  keyObj.pwd = newPwd
  keyObj.jwtToken = randomStr(32)
  await keyDB.updateAsync({ _id: keyObj._id }, { $set: keyObj })
  try {
    await revokeAllSessions(sessionDB)
  } finally {
    // 已建立的长连接不会再次经过鉴权，必须主动断开。
    disconnectAllSessionConnections()
  }
  ctx.cookies.set('session', '', {
    httpOnly: true,
    expires: new Date(0),
    sameSite: 'strict',
    secure: cookieSecure
  })
  sendNoticeAsync('updatePwd', '用户密码修改提醒', `原用户名：${ user }\n更新用户名: ${ newLoginName }`)
  res.success({ data: true, msg: '修改成功，请重新登录' })
}

const getEasynodeVersion = async ({ res }) => {
  try {
    // const { data } = await axios.get('https://api.github.com/repos/chaos-zhu/easynode/releases/latest')
    const { data } = await axios.get('https://get-easynode-latest-version.chaoszhu.workers.dev/version')
    res.success({ data, msg: 'success' })
  } catch (error) {
    logger.error('Failed to fetch Easynode latest version:', error)
    res.fail({ msg: 'Failed to fetch Easynode latest version' })
  }
}

let tempSecret = null
const getMFA2Status = async ({ res }) => {
  const { enableMFA2 = false } = await keyDB.findOneAsync({})
  res.success({ data: enableMFA2, msg: 'success' })
}
const getMFA2Code = async ({ res }) => {
  const { user } = await keyDB.findOneAsync({})
  let { otpauth_url, base32 } = speakeasy.generateSecret({ name: `EasyNode-${ user }`, length: 20 })
  tempSecret = base32
  const qrImage = await QRCode.toDataURL(otpauth_url)
  const data = { qrImage, secret: tempSecret }
  res.success({ data, msg: 'success' })
}

const enableMFA2 = async ({ res, request }) => {
  const { body: { token } } = request
  if (!token) return res.fail({ data: false, msg: '参数错误' })
  try {
    // const isValid = authenticator.verify({ token, secret: tempSecret })
    const isValid = speakeasy.totp.verify({ secret: tempSecret, encoding: 'base32', token, window: 1 })
    if (!isValid) return res.fail({ msg: '验证失败' })
    const keyConfig = await keyDB.findOneAsync({})
    keyConfig.enableMFA2 = true
    keyConfig.secret = tempSecret
    tempSecret = null
    await keyDB.updateAsync({ _id: keyConfig._id }, { $set: keyConfig })
    res.success({ msg: '验证成功' })
  } catch (error) {
    logger.error('MFA2验证失败:', error.message)
    res.fail({ msg: `验证失败: ${ error.message }` })
  }
}

const disableMFA2 = async ({ res, request }) => {
  const { body: { token } } = request
  if (!token) return res.fail({ data: false, msg: '请输入MFA2验证码' })

  try {
    const keyConfig = await keyDB.findOneAsync({})
    const { secret } = keyConfig

    // 验证MFA2 token
    const isValid = speakeasy.totp.verify({ secret, encoding: 'base32', token: String(token), window: 1 })
    if (!isValid) return res.fail({ msg: '验证码错误' })

    // 验证通过，禁用MFA2
    keyConfig.enableMFA2 = false
    keyConfig.secret = null
    await keyDB.updateAsync({ _id: keyConfig._id }, { $set: keyConfig })
    res.success({ msg: '禁用成功' })
  } catch (error) {
    logger.error('禁用MFA2失败:', error.message)
    res.fail({ msg: `禁用失败: ${ error.message }` })
  }
}

const getPlusInfo = async ({ res }) => {
  const dbData = (await plusDB.findOneAsync({})) || {}
  delete dbData._id
  delete dbData.decryptKey

  // 运行时真实激活状态：内存里 decryptKey 在 + 未被踢 = 真正可用
  const kicked = runtimeState.getPlusKicked()
  const active = Boolean(runtimeState.getDecryptKey()) && !kicked
  const data = {
    key: dbData.key || '',
    instanceId: dbData.instanceId || '',
    active, // 前端/移动端用这个判断「Plus 正常激活使用中」
    status: active ? 'active'
      : kicked ? 'kicked'
        : dbData.key ? 'inactive' : 'unset',
    needRestart: kicked,
    tokenExpireAt: runtimeState.getTokenExpireAt() || 0,
    error: kicked
      ? '授权已在其它实例被占用，重启服务后重试'
      : ''
  }
  res.success({ data, msg: 'success' })
}

const getPlusDiscount = async ({ res } = {}) => {
  // if (process.env.EXEC_ENV === 'local') return res.success({ discount: false })

  try {
    const response = await requestWithFailover(`/api/announcement/public?version=${ version }`)

    if (response.ok) {
      const data = await response.json()
      return res.success({ data, msg: 'success' })
    }

    // 如果是403或其他错误状态码
    logger.error('获取折扣信息失败，状态码:', response.status)
    return res.success({ discount: false })

  } catch (error) {
    logger.error('获取折扣信息失败:', error.message)
    return res.success({ discount: false })
  }
}

const getPlusConf = async ({ res }) => {
  const { key } = await plusDB.findOneAsync({}) || {}
  res.success({ data: key || '', msg: 'success' })
}

const updatePlusKey = async ({ res, request }) => {
  const { body: { key } } = request
  if (runtimeState.getPlusKicked()) {
    runtimeState.clearSessionId()
    return res.fail({ data: { needRestart: true }, msg: '检测到授权已在其它实例被占用，请重启面板服务后重试' })
  }
  const { success, msg, needRestart } = await getLicenseInfo(key)
  if (!success) return res.fail({ data: { needRestart }, msg })
  res.success({ msg: 'success' })
}

const getPlusDevices = async ({ res }) => {
  if (runtimeState.getPlusKicked()) return res.fail({ data: { needRestart: true }, msg: '授权已在其它实例被占用，请重启面板服务后重试' })
  const { key, instanceId } = (await plusDB.findOneAsync({})) || {}
  const sessionId = runtimeState.getSessionId()
  if (!key || !instanceId || !sessionId) return res.fail({ msg: 'Plus未激活' })
  try {
    const response = await requestWithFailover('/api/plus/devices', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, instanceId, sessionId, version })
    })
    const body = await response.json().catch(() => ({}))
    if (!response.ok || !body?.success) return res.fail({ msg: body?.message || '获取设备列表失败' })
    res.success({ data: body.data })
  } catch (error) {
    logger.error(`获取Plus设备列表失败: ${ error?.message || error }`)
    res.fail({ msg: error?.message || '获取设备列表失败' })
  }
}

const releasePlusDevice = async ({ res, request }) => {
  if (runtimeState.getPlusKicked()) return res.fail({ data: { needRestart: true }, msg: '授权已在其它实例被占用，请重启面板服务后重试' })
  const { targetInstanceId } = request.body
  const { key, instanceId } = (await plusDB.findOneAsync({})) || {}
  const sessionId = runtimeState.getSessionId()
  if (!key || !instanceId || !sessionId) return res.fail({ msg: 'Plus未激活' })
  if (!targetInstanceId || targetInstanceId === instanceId) return res.fail({ msg: '不能释放本机' })
  try {
    const response = await requestWithFailover('/api/plus/release', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, instanceId, sessionId, version, targetInstanceId })
    })
    const body = await response.json().catch(() => ({}))
    if (!response.ok || !body?.success) return res.fail({ msg: body?.message || '释放失败' })
    res.success({ msg: '释放成功' })
  } catch (error) {
    logger.error(`释放Plus设备失败: ${ error?.message || error }`)
    res.fail({ msg: error?.message || '释放失败' })
  }
}

export {
  login,
  getpublicKey,
  updatePwd,
  getEasynodeVersion,
  getMFA2Status,
  getMFA2Code,
  enableMFA2,
  disableMFA2,
  getPlusInfo,
  getPlusDiscount,
  getPlusConf,
  updatePlusKey,
  getPlusDevices,
  releasePlusDevice
}
