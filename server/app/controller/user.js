const jwt = require('jsonwebtoken')
const axios = require('axios')
const { getNetIPInfo, readKey, writeKey, RSADecryptSync, AESEncryptSync, SHA1Encrypt } = require('../utils')
const { asyncSendNotice } = require('../utils/notify')

const getpublicKey = async ({ res }) => {
  let { publicKey: data } = await readKey()
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
  let { body: { loginName, ciphertext, jwtExpires }, ip: clientIp } = request
  if (!loginName && !ciphertext) return res.fail({ msg: '请求非法!' })
  if (forbidLogin) return res.fail({ msg: `禁止登录! 倒计时[${ loginCountDown }s]后尝试登录或重启面板服务` })
  loginErrCount++
  loginErrTotal++
  if (loginErrCount >= allowErrCount) {
    const { ip, country, city } = await getNetIPInfo(clientIp)
    // 异步发送通知&禁止登录
    asyncSendNotice('err_login', '登录错误提醒', `错误登录次数: ${ loginErrTotal }<br/>地点：${ country + city }<br/>IP: ${ ip }`)
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
    // console.log('ciphertext', ciphertext)
    let loginPwd = await RSADecryptSync(ciphertext)
    // console.log('Decrypt解密password:', loginPwd)
    let { user, pwd } = await readKey()
    if (loginName === user && loginPwd === 'admin' && pwd === 'admin') {
      const token = await beforeLoginHandler(clientIp, jwtExpires)
      return res.success({ data: { token, jwtExpires }, msg: '登录成功，请及时修改默认用户名和密码' })
    }
    loginPwd = SHA1Encrypt(loginPwd)
    if (loginName !== user || loginPwd !== pwd) return res.fail({ msg: `用户名或密码错误 ${ loginErrTotal }/${ allowErrCount }` })
    const token = await beforeLoginHandler(clientIp, jwtExpires)
    return res.success({ data: { token, jwtExpires }, msg: '登录成功' })
  } catch (error) {
    console.log('解密失败：', error)
    res.fail({ msg: '解密失败, 请查看服务端日志' })
  }
}

const beforeLoginHandler = async (clientIp, jwtExpires) => {
  loginErrCount = loginErrTotal = 0 // 登录成功, 清空错误次数

  // consola.success('登录成功, 准备生成token', new Date())
  // 生产token
  let { commonKey } = await readKey()
  let token = jwt.sign({ date: Date.now() }, commonKey, { expiresIn: jwtExpires }) // 生成token
  token = await AESEncryptSync(token) // 对称加密token后再传输给前端

  // 记录客户端登录IP(用于判断是否异地且只保留最近10条)
  const clientIPInfo = await getNetIPInfo(clientIp)
  const { ip, country, city } = clientIPInfo || {}
  consola.info('登录成功:', new Date(), { ip, country, city })

  // 邮件登录通知
  asyncSendNotice('login', '登录提醒', `地点：${ country + city }<br/>IP: ${ ip }`)

  global.loginRecord.unshift(clientIPInfo)
  if (global.loginRecord.length > 10) global.loginRecord = global.loginRecord.slice(0, 10)
  return token
}

const updatePwd = async ({ res, request }) => {
  let { body: { oldLoginName, oldPwd, newLoginName, newPwd } } = request
  let rsaOldPwd = await RSADecryptSync(oldPwd)
  oldPwd = rsaOldPwd === 'admin' ? 'admin' : SHA1Encrypt(rsaOldPwd)
  let keyObj = await readKey()
  let { user, pwd } = keyObj
  if (oldLoginName !== user || oldPwd !== pwd) return res.fail({ data: false, msg: '原用户名或密码校验失败' })
  // 旧密钥校验通过，加密保存新密码
  newPwd = await RSADecryptSync(newPwd) === 'admin' ? 'admin' : SHA1Encrypt(await RSADecryptSync(newPwd))
  keyObj.user = newLoginName
  keyObj.pwd = newPwd
  await writeKey(keyObj)

  asyncSendNotice('updatePwd', '用户密码修改提醒', `原用户名：${ user }<br/>更新用户名: ${ newLoginName }`)

  res.success({ data: true, msg: 'success' })
}

const getLoginRecord = async ({ res }) => {
  res.success({ data: global.loginRecord, msg: 'success' })
}

const getEasynodeVersion = async ({ res }) => {
  try {
    // const { data } = await axios.get('https://api.github.com/repos/chaos-zhu/easynode/releases/latest')
    const { data } = await axios.get('https://get-easynode-latest-version.chaoszhu.workers.dev/version')
    console.log(data)
    res.success({ data, msg: 'success' })
  } catch (error) {
    consola.error('Failed to fetch Easynode latest version:', error)
    res.fail({ msg: 'Failed to fetch Easynode latest version' })
  }
}

module.exports = {
  login,
  getpublicKey,
  updatePwd,
  getLoginRecord,
  getEasynodeVersion
}
