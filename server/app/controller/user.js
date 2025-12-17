const jwt = require('jsonwebtoken')
const axios = require('axios')
const speakeasy = require('speakeasy')
const QRCode = require('qrcode')
const uap = require('ua-parser-js')
const { v4: uuidv4 } = require('uuid')
const version = require('../../package.json').version
const getLicenseInfo = require('../utils/get-plus')
const { sendNoticeAsync } = require('../utils/notify')
const { RSADecryptAsync, AESEncryptAsync, SHA1Encrypt } = require('../utils/encrypt')
const { getNetIPInfo, requestWithFailover } = require('../utils/tools')
const { KeyDB, PlusDB, SessionDB } = require('../utils/db-class')

const keyDB = new KeyDB().getInstance()
const sessionDB = new SessionDB().getInstance()
const plusDB = new PlusDB().getInstance()

const getpublicKey = async ({ res }) => {
  let { publicKey: data } = await keyDB.findOneAsync({})
  if (!data) return res.fail({ msg: 'publicKey not found, Try to restart the server', status: 500 })
  res.success({ data })
}

let timer = null
const allowErrCount = 5 // 允许错误的次数
const forbidTimer = 60 * 5 // 禁止登录时间
let loginErrCount = 0 // 每一轮的登录错误次数
let loginErrTotal = 0 // 总的登录错误次数
let loginCountDown = forbidTimer
let forbidLogin = false

const login = async ({ res, request }) => {
  let { body: { loginName, ciphertext, jwtExpires, jwtExpireAt, mfa2Token }, ip: clientIp, header } = request
  if (!loginName || !ciphertext || !jwtExpires || !jwtExpireAt || !header) return res.fail({ msg: '请求非法!' })
  if (forbidLogin) return res.fail({ msg: `禁止登录! 倒计时[${ loginCountDown }s]后尝试登录或重启面板服务` })
  loginErrCount++
  loginErrTotal++
  if (loginErrCount >= allowErrCount) {
    const { ip, country, city } = await getNetIPInfo(clientIp)
    // 异步发送通知&禁止登录
    sendNoticeAsync('err_login', '登录错误提醒', `错误登录次数: ${ loginErrTotal }\n地点：${ country + city }\nIP: ${ ip }`)
    forbidLogin = true
    loginErrCount = 0

    // forbidTimer秒后解禁
    setTimeout(() => {
      forbidLogin = false
    }, loginCountDown * 1000)

    // 计算登录倒计时
    timer = setInterval(() => {
      if (loginCountDown <= 0) {
        clearInterval(timer)
        timer = null
        loginCountDown = forbidTimer
        return
      }
      loginCountDown--
    }, 1000)
  }

  // 登录流程
  try {
    let loginPwd = await RSADecryptAsync(ciphertext)
    let { user, pwd, enableMFA2, secret, _id } = await keyDB.findOneAsync({})
    if (enableMFA2) {
      const isValid = speakeasy.totp.verify({ secret, encoding: 'base32', token: String(mfa2Token), window: 1 })
      console.log('MFA2 verfify:', isValid)
      if (!isValid) return res.fail({ msg: '验证失败' })
    }

    // 统一使用SHA1加密验证
    loginPwd = SHA1Encrypt(loginPwd)
    if (loginName !== user || loginPwd !== pwd) return res.fail({ msg: `用户名或密码错误 ${ loginErrTotal }/${ allowErrCount }` })

    const { token, deviceId } = await beforeLoginHandler(clientIp, jwtExpires, jwtExpireAt, uap(header?.['user-agent'] || ''))
    return res.success({ data: { token, uid: _id, deviceId }, msg: '登录成功' })
  } catch (error) {
    console.log('登录失败：', error.message)
    res.fail({ msg: '登录失败, 请查看服务端日志' })
  }
}

const beforeLoginHandler = async (clientIp, jwtExpires, jwtExpireAt, agentInfo) => {
  loginErrCount = loginErrTotal = 0 // 登录成功, 清空错误次数
  const sessionId = uuidv4()
  const deviceId = uuidv4()
  let { jwtToken, user } = await keyDB.findOneAsync({})
  if (!jwtToken || !user) throw new Error('加密串获取失败，请重启服务!')
  let token = jwt.sign({ create: Date.now(), sid: sessionId }, `${ jwtToken }-${ user }`, { expiresIn: jwtExpires })
  token = await AESEncryptAsync(token) // 对称加密token后再传输给前端

  const clientIPInfo = await getNetIPInfo(clientIp)
  const { ip, country, city } = clientIPInfo || {}
  logger.info('登录成功:', { ip, country, city, agentInfo })

  // 登录通知
  sendNoticeAsync('login', '登录提醒', `地点：${ country + city }\nIP: ${ ip }\n设备信息: ${ agentInfo?.browser?.name } ${ agentInfo?.os?.name }`)

  await sessionDB.insertAsync({ sid: sessionId, deviceId, revoked: false, ip, country, city, agentInfo, create: Date.now(), expireAt: jwtExpireAt })
  return { token, deviceId }
}

const updatePwd = async ({ res, request }) => {
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
  await keyDB.updateAsync({ _id: keyObj._id }, { $set: keyObj })
  sendNoticeAsync('updatePwd', '用户密码修改提醒', `原用户名：${ user }\n更新用户名: ${ newLoginName }`)
  res.success({ data: true, msg: 'success' })
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
  let data = await plusDB.findOneAsync({})
  delete data?._id
  delete data?.decryptKey
  res.success({ data, msg: 'success' })
}

const getPlusDiscount = async ({ res } = {}) => {
  if (process.env.EXEC_ENV === 'local') return res.success({ discount: false })

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
  const { success, msg } = await getLicenseInfo(key)
  if (!success) return res.fail({ msg })
  res.success({ msg: 'success' })
}

module.exports = {
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
  updatePlusKey
}
