import NodeRSA from 'node-rsa'
import { randomStr } from './utils/tools.js'
import { AESEncryptAsync, SHA1Encrypt } from './utils/encrypt.js'
import { KeyDB, GroupDB, NotifyDB, NotifyConfigDB, ScriptGroupDB } from './utils/db-class.js'
import { initializeOrderSystem } from './services/order-service.js'
import {
  IP_ACCESS_RULE_VERSION,
  normalizeStoredIpRules,
  resolveStoredLegacyIpRules,
  setAllowedIpRules
} from './utils/ip-access.js'

async function initKeyDB() {
  const keyDB = new KeyDB().getInstance()
  let keyData = await keyDB.findOneAsync({})

  if (keyData?.user) {

    if (!keyData?.jwtToken) {
      logger.info('🔒初始化jwtToken')
      const jwtToken = randomStr(32)
      await keyDB.updateAsync({ _id: keyData._id }, { $set: { jwtToken } })
    }

    try {
      const { ipWhiteList = [] } = keyData
      const normalizedRules = normalizeStoredIpRules(ipWhiteList)
      const legacyRules = resolveStoredLegacyIpRules({
        rules: normalizedRules,
        legacyRules: keyData.ipAccessLegacyRules,
        ruleVersion: keyData.ipAccessRuleVersion
      })
      setAllowedIpRules(normalizedRules, { legacyRules })

      if (Number(keyData.ipAccessRuleVersion) < IP_ACCESS_RULE_VERSION ||
        !Number.isFinite(Number(keyData.ipAccessRuleVersion))) {
        await keyDB.updateAsync({ _id: keyData._id }, {
          $set: {
            ipWhiteList: normalizedRules,
            ipAccessLegacyRules: legacyRules,
            ipAccessRuleVersion: IP_ACCESS_RULE_VERSION
          }
        })
        logger.info(`旧版 IP 白名单已迁移为 ${ legacyRules.length } 条 legacy 访问规则`)
      }
    } catch (error) {
      logger.error('设置全局IP白名单失败:', error)
    }
    logger.info('公私钥已存在[重新生成会导致已保存的ssh密钥信息失效]')
    return
  }

  const randomUsername = randomStr(8)
  const randomPassword = randomStr(8)

  let newConfig = {
    user: randomUsername,
    pwd: SHA1Encrypt(randomPassword),
    commonKey: randomStr(32),
    jwtToken: randomStr(32),
    ipWhiteList: [],
    ipAccessLegacyRules: [],
    ipAccessRuleVersion: IP_ACCESS_RULE_VERSION,
    publicKey: '',
    privateKey: ''
  }
  await keyDB.insertAsync(newConfig)
  let key = new NodeRSA({ b: 2048 })
  key.setOptions({ encryptionScheme: 'pkcs1', environment: 'browser' })
  let privateKey = key.exportKey('pkcs1-private-pem')
  let publicKey = key.exportKey('pkcs8-public-pem')
  newConfig.privateKey = await AESEncryptAsync(privateKey, newConfig.commonKey) // 加密私钥
  newConfig.publicKey = publicKey // 公开公钥
  await keyDB.updateAsync({}, { $set: newConfig }, { upsert: true })

  // 在控制台打印随机生成的账号密码
  logger.info('========================================')
  logger.info('EasyNode 默认登录凭据 (请及时更改):')
  logger.info(`用户名: ${ randomUsername }`)
  logger.info(`密码: ${ randomPassword }`)
  logger.info('========================================')

}

async function initGroupDB() {
  const groupDB = new GroupDB().getInstance()
  const defaultGroup = await groupDB.findOneAsync({ _id: 'default' })
  if (!defaultGroup) {
    logger.info('初始化groupDB✔')
    return groupDB.insertAsync({ '_id': 'default', 'name': '默认分组' })
  }
  return Promise.resolve()
}

async function initNotifyDB() {
  const notifyDB = new NotifyDB().getInstance()
  const defaultData = [{
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
  }, {
    'type': 'scheduled_task_execution',
    'desc': '定时任务执行通知',
    'sw': false
  }]
  const existing = await notifyDB.findAsync({})
  const existingTypes = new Set(existing.map(item => item.type))
  const missing = defaultData.filter(item => !existingTypes.has(item.type))
  if (!missing.length) return
  logger.info('初始化notifyDB✔')
  return notifyDB.insertAsync(missing)
}

async function initNotifyConfigDB() {
  const notifyConfigDB = new NotifyConfigDB().getInstance()
  let notifyConfig = await notifyConfigDB.findOneAsync({})
  logger.info('初始化NotifyConfigDB✔')
  const defaultData = {
    type: 'sct',
    sct: {
      sendKey: ''
    },
    email: {
      service: 'QQ',
      user: '',
      pass: '',
      useCustom: false,
      host: '',
      port: 465,
      secure: true,
      to: ''
    },
    tg: {
      token: '',
      chatId: ''
    },
    webhook: {
      url: '',
      method: 'POST',
      contentType: 'application/json',
      headers: '',
      template: '{\n  "title": "{{title}}",\n  "content": "{{content}}",\n  "description": "{{content}}",\n  "timestamp": "{{timestamp}}",\n  "datetime": "{{datetime}}"\n}'
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
  const [defaultGroup, builtinGroup] = await Promise.all([
    scriptGroupDB.findOneAsync({ _id: 'default' }),
    scriptGroupDB.findOneAsync({ _id: 'builtin' })
  ])
  const missing = []
  if (!defaultGroup) missing.push({ '_id': 'default', 'name': '默认分组' })
  if (!builtinGroup) missing.push({ '_id': 'builtin', 'name': '内置脚本' })
  if (missing.length) {
    logger.info('初始化ScriptGroupDB✔')
    return scriptGroupDB.insertAsync(missing)
  }
  return Promise.resolve()
}

export default async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initScriptGroupDB()
  await initNotifyConfigDB()
  await initializeOrderSystem()
}
