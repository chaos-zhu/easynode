const { writeKey, writeNotifyList, writeGroupList } = require('./utils/storage')
const { KeyDB, NotifyDB, GroupDB, EmailNotifyDB } = require('./utils/db-class')
const { readScriptList, writeScriptList } = require('./utils')

function initKeyDB() {
  return new Promise((resolve, reject) => {
    const keyDB = new KeyDB().getInstance()
    keyDB.count({}, async (err, count) => {
      if (err) {
        consola.log('初始化keyDB错误:', err)
        reject(err)
      } else {
        if (count === 0) {
          consola.log('初始化keyDB✔')
          const defaultData = {
            user: 'admin',
            pwd: 'admin',
            commonKey: '',
            publicKey: '',
            privateKey: ''
          }
          await writeKey(defaultData)
        }
      }
      resolve()
    })
  })
}

function initNotifyDB() {
  return new Promise((resolve, reject) => {
    const notifyDB = new NotifyDB().getInstance()
    notifyDB.count({}, async (err, count) => {
      if (err) {
        consola.log('初始化notifyDB错误:', err)
        reject(err)
      } else {
        if (count === 0) {
          consola.log('初始化notifyDB✔')
          const defaultData = [{
            'type': 'login',
            'desc': '登录面板提醒',
            'sw': true
          },
          {
            'type': 'err_login',
            'desc': '登录错误提醒(连续5次)',
            'sw': true
          },
          {
            'type': 'updatePwd',
            'desc': '修改密码提醒',
            'sw': true
          },
          {
            'type': 'host_offline',
            'desc': '客户端离线提醒(每小时最多发送一次提醒)',
            'sw': true
          }]
          await writeNotifyList(defaultData)
        }

      }
      resolve()
    })
  })
}

function initGroupDB() {
  return new Promise((resolve, reject) => {
    const groupDB = new GroupDB().getInstance()
    groupDB.count({}, async (err, count) => {
      if (err) {
        consola.log('初始化groupDB错误:', err)
        reject(err)
      } else {
        if (count === 0) {
          consola.log('初始化groupDB✔')
          const defaultData = [{ '_id': 'default', 'name': '默认分组', 'index': 0 }]
          await writeGroupList(defaultData)
        }
      }
      resolve()
    })
  })
}

function initEmailNotifyDB() {
  return new Promise((resolve, reject) => {
    const emailNotifyDB = new EmailNotifyDB().getInstance()
    emailNotifyDB.count({}, async (err, count) => {
      if (err) {
        consola.log('初始化emailNotifyDB错误:', err)
        reject(err)
      } else {
        if (count === 0) {
          consola.log('初始化emailNotifyDB✔')
          const defaultData = {
            'support': [
              {
                'name': 'QQ邮箱',
                'target': 'qq',
                'host': 'smtp.qq.com',
                'port': 465,
                'secure': true,
                'tls': {
                  'rejectUnauthorized': false
                }
              },
              {
                'name': '网易126',
                'target': 'wangyi126',
                'host': 'smtp.126.com',
                'port': 465,
                'secure': true,
                'tls': {
                  'rejectUnauthorized': false
                }
              },
              {
                'name': '网易163',
                'target': 'wangyi163',
                'host': 'smtp.163.com',
                'port': 465,
                'secure': true,
                'tls': {
                  'rejectUnauthorized': false
                }
              }
            ],
            'user': [
            ]
          }
          emailNotifyDB.update({}, { $set: defaultData }, { upsert: true }, (err, numReplaced) => {
            if (err) {
              reject(err)
            } else {
              emailNotifyDB.compactDatafile()
              resolve(numReplaced)
            }
          })
        } else {
          resolve()
        }
      }
    })
  })
}

function initScriptsDB() {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise(async (resolve) => {
    let scriptList = await readScriptList()
    let clientInstallScript = 'wget https://mirror.ghproxy.com/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh && sh easynode-client-install.sh'
    let clientUninstallScript = 'wget https://mirror.ghproxy.com/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-uninstall.sh && sh easynode-client-uninstall.sh'
    let clientVersion = process.env.CLIENT_VERSION
    consola.info('客户端版本：', clientVersion)
    let installId = `clientInstall${ clientVersion }`
    let uninstallId = `clientUninstall${ clientVersion }`

    let isClientInstall = scriptList?.find(script => script._id = installId)
    let isClientUninstall = scriptList?.find(script => script._id = uninstallId)
    let writeFlag = false
    if (!isClientInstall) {
      console.info('初始化客户端安装脚本')
      scriptList.push({ _id: installId, name: `easynode-客户端-${ clientVersion }安装脚本`, remark: '系统内置|重启生成', content: clientInstallScript, index: 1 })
      writeFlag = true
    } else {
      console.info('客户端安装脚本已存在')
    }
    if (!isClientUninstall) {
      console.info('初始化客户端卸载脚本')
      scriptList.push({ _id: uninstallId, name: `easynode-客户端-${ clientVersion }卸载脚本`, remark: '系统内置|重启生成', content: clientUninstallScript, index: 0 })
      writeFlag = true
    } else {
      console.info('客户端卸载脚本已存在')
    }
    if (writeFlag) await writeScriptList(scriptList)
    resolve()
  })
}

module.exports = async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initEmailNotifyDB()
  await initScriptsDB()
}