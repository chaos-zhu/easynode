const { KeyDB, SshRecordDB, OnekeyDB } = require('./db-class')

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

module.exports = {
  readSSHRecord, writeSSHRecord,
  readKey, writeKey
}
