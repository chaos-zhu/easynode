const { writeKey, writeGroupList, writeNotifyList, writeNotifyConfig } = require('./utils/storage')
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

function initNotifyDB() {
  return new Promise((resolve, reject) => {
    const notifyDB = new NotifyDB().getInstance()
    notifyDB.find({}, async (err, notifyList) => {
      if (err) {
        consola.log('初始化notifyDB错误:', err)
        reject(err)
      } else {
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
        if (notifyList.length === 0) {
          consola.log('初始化notifyDB✔')
        } else {
          consola.log('同步notifyDB✔')
          defaultData = defaultData.map(defaultItem => {
            let item = notifyList.find(notify => notify.type === defaultItem.type)
            defaultItem.sw = item ? item.sw : false
            return item
          })
        }
        await writeNotifyList(defaultData)
      }
      resolve()
    })
  })
}

function initNotifyConfigDB() {
  return new Promise((resolve, reject) => {
    const notifyConfigDB = new NotifyConfigDB().getInstance()
    notifyConfigDB.count({}, async (err, count) => {
      if (err) {
        consola.log('初始化NotifyConfigDB错误:', err)
        reject(err)
      } else {
        if (count === 0) {
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
          await writeNotifyConfig(defaultData)
        }
      }
      resolve()
    })
  })
}

module.exports = async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initNotifyConfigDB()
}
