const NodeRSA = require('node-rsa')
const { randomStr } = require('./utils/tools')
const { AESEncryptAsync } = require('./utils/encrypt')
const { KeyDB, GroupDB, NotifyDB, NotifyConfigDB, ScriptGroupDB } = require('./utils/db-class')

async function initKeyDB() {
  const keyDB = new KeyDB().getInstance()
  let keyData = await keyDB.findOneAsync({})
  if (keyData?.user) {
    const { _id, ipWhiteList } = keyData
    let allowedIPs = process.env.ALLOWED_IPS ? process.env.ALLOWED_IPS.split(',') : []
    if (allowedIPs.length > 0) {
      consola.info('[存在白名单IP环境变量,合并到本地数据库中]')
      allowedIPs = [...new Set([...ipWhiteList, ...allowedIPs])].filter(item => item)
      await keyDB.updateAsync({ _id }, { $set: { ipWhiteList: allowedIPs } })
    }
    consola.info('公私钥已存在[重新生成会导致已保存的ssh密钥信息失效]')
    return
  }
  let newConfig = {
    user: 'admin',
    pwd: 'admin',
    commonKey: randomStr(16),
    publicKey: '',
    privateKey: ''
  }
  await keyDB.insertAsync(newConfig)
  let key = new NodeRSA({ b: 1024 })
  key.setOptions({ encryptionScheme: 'pkcs1', environment: 'browser' })
  let privateKey = key.exportKey('pkcs1-private-pem')
  let publicKey = key.exportKey('pkcs8-public-pem')
  newConfig.privateKey = await AESEncryptAsync(privateKey, newConfig.commonKey) // 加密私钥
  newConfig.publicKey = publicKey // 公开公钥
  await keyDB.updateAsync({}, { $set: newConfig }, { upsert: true })
  consola.info('Task: 已生成新的非对称加密公私钥')
}

async function initGroupDB() {
  const groupDB = new GroupDB().getInstance()
  let count = await groupDB.countAsync({})
  if (count === 0) {
    consola.log('初始化groupDB✔')
    const defaultData = [{ '_id': 'default', 'name': '默认分组', 'index': 0 }]
    return groupDB.insertAsync(defaultData)
  }
  return Promise.resolve()
}

async function initNotifyDB() {
  const notifyDB = new NotifyDB().getInstance()
  let count = await notifyDB.countAsync({})
  if (count !== 0) return
  consola.log('初始化notifyDB✔')
  let defaultData = [{
    'type': 'login',
    'desc': '登录面板提醒',
    'sw': false
  }, {
    'type': 'err_login',
    'desc': '登录错误提醒(连续5次)',
    'sw': false
  }, {
    'type': 'updatePwd',
    'desc': '修改密码提醒',
    'sw': false
  }, {
    'type': 'host_login',
    'desc': '服务器登录提醒',
    'sw': false
  }, {
    'type': 'onekey_complete',
    'desc': '批量指令执行完成提醒',
    'sw': false
  }, {
    'type': 'host_expired',
    'desc': '服务器到期提醒',
    'sw': false
  }]
  return notifyDB.insertAsync(defaultData)
}

async function initNotifyConfigDB() {
  const notifyConfigDB = new NotifyConfigDB().getInstance()
  let notifyConfig = await notifyConfigDB.findOneAsync({})
  consola.log('初始化NotifyConfigDB✔')
  const defaultData = {
    type: 'sct',
    sct: {
      sendKey: ''
    },
    email: {
      service: 'QQ',
      user: '',
      pass: ''
    },
    tg: {
      token: '',
      chatId: ''
    }
  }
  if (notifyConfig) {
    await notifyConfigDB.removeAsync({ _id: notifyConfig._id })
    delete notifyConfig._id
    return notifyConfigDB.insertAsync(Object.assign({}, defaultData, notifyConfig))
  }
  return notifyConfigDB.insertAsync(defaultData)
}

async function initScriptGroupDB() {
  const scriptGroupDB = new ScriptGroupDB().getInstance()
  let count = await scriptGroupDB.countAsync({})
  if (count === 0) {
    consola.log('初始化ScriptGroupDB✔')
    const defaultData = [
      { '_id': 'default', 'name': '默认分组', 'index': 0 },
      { '_id': 'builtin', 'name': '内置脚本', 'index': -1 }
    ]
    return scriptGroupDB.insertAsync(defaultData)
  }
  return Promise.resolve()
}

module.exports = async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initScriptGroupDB()
  await initNotifyConfigDB()
}
