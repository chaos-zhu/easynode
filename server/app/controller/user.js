const jwt = require('jsonwebtoken')
const axios = require('axios')
const speakeasy = require('speakeasy')
const QRCode = require('qrcode')
const { sendNoticeAsync } = require('../utils/notify')
const { RSADecryptAsync, AESEncryptAsync, SHA1Encrypt } = require('../utils/encrypt')
const { getNetIPInfo } = require('../utils/tools')
const { KeyDB, LogDB, PlusDB } = require('../utils/db-class')
const keyDB = new KeyDB().getInstance()
const logDB = new LogDB().getInstance()
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
  let { body: { loginName, ciphertext, jwtExpires, mfa2Token }, ip: clientIp } = request
  if (!loginName && !ciphertext) return res.fail({ msg: '请求非法!' })
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
    let { user, pwd, enableMFA2, secret } = await keyDB.findOneAsync({})
    if (enableMFA2) {
      const isValid = speakeasy.totp.verify({ secret, encoding: 'base32', token: mfa2Token, window: 1 })
      console.log('MFA2 verfify:', isValid)
      if (!isValid) return res.fail({ msg: '验证失败' })
    }
    if (loginName === user && loginPwd === 'admin' && pwd === 'admin') {
      const token = await beforeLoginHandler(clientIp, jwtExpires)
      return res.success({ data: { token, jwtExpires }, msg: '登录成功，请及时修改默认用户名和密码' })
    }
    loginPwd = SHA1Encrypt(loginPwd)
    if (loginName !== user || loginPwd !== pwd) return res.fail({ msg: `用户名或密码错误 ${ loginErrTotal }/${ allowErrCount }` })
    const token = await beforeLoginHandler(clientIp, jwtExpires)
    return res.success({ data: { token, jwtExpires }, msg: '登录成功' })
  } catch (error) {
    console.log('登录失败：', error.message)
    res.fail({ msg: '登录失败, 请查看服务端日志' })
  }
}

const beforeLoginHandler = async (clientIp, jwtExpires) => {
  loginErrCount = loginErrTotal = 0 // 登录成功, 清空错误次数

  // consola.success('登录成功, 准备生成token', new Date())
  // 生产token
  let { commonKey } = await keyDB.findOneAsync({})
  let token = jwt.sign({ date: Date.now() }, commonKey, { expiresIn: jwtExpires }) // 生成token
  token = await AESEncryptAsync(token) // 对称加密token后再传输给前端

  // 记录客户端登录IP(用于判断是否异地且只保留最近10条)
  const clientIPInfo = await getNetIPInfo(clientIp)
  const { ip, country, city } = clientIPInfo || {}
  consola.info('登录成功:', new Date(), { ip, country, city })

  // 登录通知
  sendNoticeAsync('login', '登录提醒', `地点：${ country + city }\nIP: ${ ip }`)

  await logDB.insertAsync({ ip, country, city, date: Date.now(), type: 'login' })
  return token
}

const updatePwd = async ({ res, request }) => {
  let { body: { oldLoginName, oldPwd, newLoginName, newPwd } } = request
  let rsaOldPwd = await RSADecryptAsync(oldPwd)
  oldPwd = rsaOldPwd === 'admin' ? 'admin' : SHA1Encrypt(rsaOldPwd)
  let keyObj = await keyDB.findOneAsync({})
  let { user, pwd } = keyObj
  if (oldLoginName !== user || oldPwd !== pwd) return res.fail({ data: false, msg: '原用户名或密码校验失败' })
  // 旧密钥校验通过，加密保存新密码
  newPwd = await RSADecryptAsync(newPwd) === 'admin' ? 'admin' : SHA1Encrypt(await RSADecryptAsync(newPwd))
  keyObj.user = newLoginName
  keyObj.pwd = newPwd
  await keyDB.updateAsync({}, keyObj)
  sendNoticeAsync('updatePwd', '用户密码修改提醒', `原用户名：${ user }\n更新用户名: ${ newLoginName }`)
  res.success({ data: true, msg: 'success' })
}

const getEasynodeVersion = async ({ res }) => {
  try {
    // const { data } = await axios.get('https://api.github.com/repos/chaos-zhu/easynode/releases/latest')
    const { data } = await axios.get('https://get-easynode-latest-version.chaoszhu.workers.dev/version')
    res.success({ data, msg: 'success' })
  } catch (error) {
    consola.error('Failed to fetch Easynode latest version:', error)
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
    await keyDB.updateAsync({}, keyConfig)
    res.success({ msg: '验证成功' })
  } catch (error) {
    res.fail({ msg: `验证失败: ${ error.message }` })
  }
}

const disableMFA2 = async ({ res }) => {
  const keyConfig = await keyDB.findOneAsync({})
  keyConfig.enableMFA2 = false
  keyConfig.secret = null
  await keyDB.updateAsync({}, keyConfig)
  res.success({ msg: 'success' })
}

const getPlusInfo = async ({ res }) => {
  let data = await plusDB.findOneAsync({})
  delete data?._id
  delete data?.decryptKey
  res.success({ data, msg: 'success' })
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
  getPlusInfo
}
