const NodeRSA = require('node-rsa')
const { readKey, writeKey } = require('./utils/storage')
const { randomStr } = require('./utils/tools')
const { AESEncryptSync } = require('./utils/encrypt')

// 初始化公私钥, 供登录、保存ssh密钥/密码等加解密
async function initRsa() {
  let keyObj = await readKey()
  if (keyObj.privateKey && keyObj.publicKey) return consola.info('公私钥已存在[重新生成会导致已保存的ssh密钥信息失效]')
  let key = new NodeRSA({ b: 1024 })
  key.setOptions({ encryptionScheme: 'pkcs1', environment: 'browser' })
  let privateKey = key.exportKey('pkcs1-private-pem')
  let publicKey = key.exportKey('pkcs8-public-pem')
  keyObj.privateKey = await AESEncryptSync(privateKey) // 加密私钥
  keyObj.publicKey = publicKey // 公开公钥
  await writeKey(keyObj)
  consola.info('Task: 已生成新的非对称加密公私钥')
}

// 随机的commonKey secret
async function randomJWTSecret() {
  let keyObj = await readKey()
  if (keyObj?.commonKey) return consola.info('commonKey密钥已存在')

  keyObj.commonKey = randomStr(16)
  await writeKey(keyObj)
  consola.info('Task: 已生成新的随机commonKey密钥')
}

module.exports = async () => {
  await randomJWTSecret() // 全局密钥
  await initRsa() // 全局公钥密钥
}
