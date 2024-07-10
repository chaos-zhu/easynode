const Datastore = require('@seald-io/nedb')
const { resolvePath } = require('./utils/tools')
const { writeKey, writeNotifyList, writeGroupList } = require('./utils/storage')
const { KeyDB, NotifyDB, GroupDB, EmailNotifyDB } = require('./utils/db-class')

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
            pwd: "admin",
            commonKey: "",
            publicKey: "",
            privateKey: ""
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
            "type": "login",
            "desc": "登录面板提醒",
            "sw": true
          },
          {
            "type": "err_login",
            "desc": "登录错误提醒(连续5次)",
            "sw": true
          },
          {
            "type": "updatePwd",
            "desc": "修改密码提醒",
            "sw": true
          },
          {
            "type": "host_offline",
            "desc": "客户端离线提醒(每小时最多发送一次提醒)",
            "sw": true
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
          const defaultData = [{ "id": "default", "name": "默认分组", "index": 0 }]
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
            "support": [
              {
                "name": "QQ邮箱",
                "target": "qq",
                "host": "smtp.qq.com",
                "port": 465,
                "secure": true,
                "tls": {
                  "rejectUnauthorized": false
                }
              },
              {
                "name": "网易126",
                "target": "wangyi126",
                "host": "smtp.126.com",
                "port": 465,
                "secure": true,
                "tls": {
                  "rejectUnauthorized": false
                }
              },
              {
                "name": "网易163",
                "target": "wangyi163",
                "host": "smtp.163.com",
                "port": 465,
                "secure": true,
                "tls": {
                  "rejectUnauthorized": false
                }
              }
            ],
            "user": [
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
module.exports = async () => {
  await initKeyDB()
  await initNotifyDB()
  await initGroupDB()
  await initEmailNotifyDB()
}