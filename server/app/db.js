const { writeKey } = require('./utils/storage')
const { KeyDB, GroupDB, NotifyDB, NotifyConfigDB } = require('./utils/db-class')

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
  let count = await notifyConfigDB.countAsync({})
  if (count !== 0) return
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
    }
  }
  return notifyConfigDB.insertAsync(defaultData)
}

module.exports = async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initNotifyConfigDB()
}
