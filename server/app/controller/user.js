const jwt = require('jsonwebtoken')
const { getNetIPInfo, readKey, writeKey, RSADecrypt, AESEncrypt, SHA1Encrypt } = require('../utils')

const getpublicKey = ({ res }) => {
  let { publicKey: data } = readKey()
  if(!data) return res.fail({ msg: 'publicKey not found, Try to restart the server', status: 500 })
  res.success({ data })
}

const generateTokenAndRecordIP = async (clientIp) => {
  console.log('密码校验成功, 准备生成token')
  let { commonKey, jwtExpires } = readKey()
  let token = jwt.sign({ date: Date.now() }, commonKey, { expiresIn: jwtExpires }) // 生成token
  token = AESEncrypt(token) // 对称加密token后再传输给前端
  console.log('aes对称加密token：：', token)

  // 记录客户端登录IP用于判断是否异地(只保留最近10条)
  const localNetIPInfo = await getNetIPInfo(clientIp)
  global.loginRecord.unshift(localNetIPInfo)
  if(global.loginRecord.length > 10) global.loginRecord = global.loginRecord.slice(0, 10)
  return { token, jwtExpires }
}

const login = async ({ res, request }) => {
  let { body: { ciphertext }, ip: clientIp } = request
  if(!ciphertext) return res.fail({ msg: '参数错误' })
  try {
    console.log('ciphertext', ciphertext)
    let password = RSADecrypt(ciphertext)
    let { pwd } = readKey()
    if(password === 'admin' && pwd === 'admin') {
      const { token, jwtExpires } = await generateTokenAndRecordIP(clientIp)
      return res.success({ data: { token, jwtExpires }, msg: '登录成功，请及时修改默认密码' })
    }
    password = SHA1Encrypt(password)
    if(password !== pwd) return res.fail({ msg: '密码错误' })
    const { token, jwtExpires } = await generateTokenAndRecordIP(clientIp)
    return res.success({ data: { token, jwtExpires }, msg: '登录成功' })
  } catch (error) {
    console.log('解密失败：', error)
    res.fail({ msg: '解密失败, 请查看服务端日志' })
  }
}

const updatePwd = async ({ res, request }) => {
  let { body: { oldPwd, newPwd } } = request
  let rsaOldPwd = RSADecrypt(oldPwd)
  oldPwd = rsaOldPwd === 'admin' ? 'admin' : SHA1Encrypt(rsaOldPwd)
  let keyObj = readKey()
  if(oldPwd !== keyObj.pwd) return res.fail({ data: false, msg: '旧密码校验失败' })
  // 旧密钥校验通过，加密保存新密码
  newPwd = SHA1Encrypt(RSADecrypt(newPwd))
  keyObj.pwd = newPwd
  writeKey(keyObj)
  res.success({ data: true, msg: 'success' })
}

const getLoginRecord = async ({ res }) => {
  res.success({ data: global.loginRecord, msg: 'success' })
}

module.exports = {
  login,
  getpublicKey,
  updatePwd,
  getLoginRecord
}
