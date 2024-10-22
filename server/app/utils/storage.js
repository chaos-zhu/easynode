const { KeyDB, SshRecordDB, NotifyDB, NotifyConfigDB, ScriptsDB, OnekeyDB } = require('./db-class')

const readKey = async () => {
  return new Promise((resolve, reject) => {
    const keyDB = new KeyDB().getInstance()
    keyDB.findOne({}, (err, doc) => {
      if (err) {
        reject(err)
      } else {
        resolve(doc)
      }
    })
  })
}

const writeKey = async (keyObj = {}) => {
  const keyDB = new KeyDB().getInstance()
  return new Promise((resolve, reject) => {
    keyDB.update({}, { $set: keyObj }, { upsert: true }, (err, numReplaced) => {
      if (err) {
        reject(err)
      } else {
        keyDB.compactDatafile()
        resolve(numReplaced)
      }
    })
  })
}

const readSSHRecord = async () => {
  const sshRecordDB = new SshRecordDB().getInstance()
  return new Promise((resolve, reject) => {
    sshRecordDB.find({}, (err, docs) => {
      if (err) {
        consola.error('读取ssh-record-db错误: ', err)
        reject(err)
      } else {
        resolve(docs)
      }
    })
  })
}

const writeSSHRecord = async (record = []) => {
  return new Promise((resolve, reject) => {
    const sshRecordDB = new SshRecordDB().getInstance()
    sshRecordDB.remove({}, { multi: true }, (err) => {
      if (err) {
        consola.error('清空SSHRecord出错:', err)
        reject(err)
      } else {
        sshRecordDB.compactDatafile()
        sshRecordDB.insert(record, (err, newDocs) => {
          if (err) {
            consola.error('写入新的ssh记录出错:', err)
            reject(err)
          } else {
            sshRecordDB.compactDatafile()
            resolve(newDocs)
          }
        })
      }
    })
  })
}

// const getNotifySwByType = async (type) => {
//   if (!type) throw Error('missing params: type')
//   try {
//     let notifyList = await readNotifyList()
//     let { sw } = notifyList.find((item) => item.type === type)
//     return sw
//   } catch (error) {
//     consola.error(`通知类型[${ type }]不存在`)
//     return false
//   }
// }

const readScriptList = async () => {
  return new Promise((resolve, reject) => {
    const scriptsDB = new ScriptsDB().getInstance()
    scriptsDB.find({}, (err, docs) => {
      if (err) {
        consola.error('读取scripts list错误: ', err)
        reject(err)
      } else {
        resolve(docs)
      }
    })
  })
}

const writeScriptList = async (list = []) => {
  return new Promise((resolve, reject) => {
    const scriptsDB = new ScriptsDB().getInstance()
    scriptsDB.remove({}, { multi: true }, (err) => {
      if (err) {
        consola.error('清空scripts list出错:', err)
        reject(err)
      } else {
        scriptsDB.compactDatafile()
        scriptsDB.insert(list, (err, newDocs) => {
          if (err) {
            consola.error('写入新的group list出错:', err)
            reject(err)
          } else {
            scriptsDB.compactDatafile()
            resolve(newDocs)
          }
        })
      }
    })
  })
}

const readOneKeyRecord = async () => {
  return new Promise((resolve, reject) => {
    const onekeyDB = new OnekeyDB().getInstance()
    onekeyDB.find({}, (err, docs) => {
      if (err) {
        consola.error('读取onekey record错误: ', err)
        reject(err)
      } else {
        onekeyDB.compactDatafile()
        resolve(docs)
      }
    })
  })
}

const writeOneKeyRecord = async (records =[]) => {
  return new Promise((resolve, reject) => {
    const onekeyDB = new OnekeyDB().getInstance()
    onekeyDB.insert(records, (err, newDocs) => {
      if (err) {
        consola.error('写入新的onekey记录出错:', err)
        reject(err)
      } else {
        onekeyDB.compactDatafile()
        resolve(newDocs)
      }
    })
  })
}

const deleteOneKeyRecord = async (ids =[]) => {
  return new Promise((resolve, reject) => {
    const onekeyDB = new OnekeyDB().getInstance()
    onekeyDB.remove({ _id: { $in: ids } }, { multi: true }, function (err, numRemoved) {
      if (err) {
        consola.error('Error deleting onekey record(s):', err)
        reject(err)
      } else {
        onekeyDB.compactDatafile()
        resolve(numRemoved)
      }
    })
  })
}

module.exports = {
  readSSHRecord, writeSSHRecord,
  readKey, writeKey,
  readScriptList, writeScriptList,
  readOneKeyRecord, writeOneKeyRecord, deleteOneKeyRecord
}
