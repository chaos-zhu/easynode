const fs = require('fs')
const { sshRecordPath, hostListPath, keyPath, emailPath, notifyPath, groupPath } = require('../config')

const readSSHRecord = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(sshRecordPath, 'utf8'))
  } catch (error) {
    consola.error('读取ssh-record错误, 即将重置ssh列表: ', error)
    writeSSHRecord([])
  }
  return list || []
}

const writeSSHRecord = (record = []) => {
  fs.writeFileSync(sshRecordPath, JSON.stringify(record, null, 2))
}

const readHostList = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(hostListPath, 'utf8'))
  } catch (error) {
    consola.error('读取host-list错误, 即将重置host列表: ', error)
    writeHostList([])
  }
  return list || []
}

const writeHostList = (record = []) => {
  fs.writeFileSync(hostListPath, JSON.stringify(record, null, 2))
}

const readKey = () => {
  let keyObj = JSON.parse(fs.readFileSync(keyPath, 'utf8'))
  return keyObj
}

const writeKey = (keyObj = {}) => {
  fs.writeFileSync(keyPath, JSON.stringify(keyObj, null, 2))
}

const readEmailJson = () => {
  let emailJson = {}
  try {
    emailJson = JSON.parse(fs.readFileSync(emailPath, 'utf8'))
  } catch (error) {
    consola.error('读取email.json错误: ', error)
  }
  return emailJson
}

const readSupportEmailList = () => {
  let supportEmailList = []
  try {
    supportEmailList = readEmailJson().support
  } catch (error) {
    consola.error('读取email support错误: ', error)
  }
  return supportEmailList
}

const readUserEmailList = () => {
  let configEmailList = []
  try {
    configEmailList = readEmailJson().user
  } catch (error) {
    consola.error('读取email config错误: ', error)
  }
  return configEmailList
}

const writeUserEmailList = (user) => {
  let support = readSupportEmailList()
  const emailJson = { support, user }
  try {
    fs.writeFileSync(emailPath, JSON.stringify(emailJson, null, 2))
    return { code: 0 }
  } catch (error) {
    return { code: -1, msg: error.message || error }
  }
}

const readNotifyList = () => {
  let notifyList = []
  try {
    notifyList = JSON.parse(fs.readFileSync(notifyPath, 'utf8'))
  } catch (error) {
    consola.error('读取notify list错误: ', error)
  }
  return notifyList
}

const getNotifySwByType = (type) => {
  if(!type) throw Error('missing params: type')
  try {
    let { sw } = readNotifyList().find((item) => item.type === type)
    return sw
  } catch (error) {
    consola.error(`通知类型[${ type }]不存在`)
    return false
  }
}

const writeNotifyList = (notifyList) => {
  fs.writeFileSync(notifyPath, JSON.stringify(notifyList, null, 2))
}

const readGroupList = () => {
  let list
  try {
    list = JSON.parse(fs.readFileSync(groupPath, 'utf8'))
  } catch (error) {
    consola.error('读取group-list错误, 即将重置group列表: ', error)
    writeSSHRecord([])
  }
  return list || []
}

const writeGroupList = (list = []) => {
  fs.writeFileSync(groupPath, JSON.stringify(list, null, 2))
}

module.exports = {
  readSSHRecord,
  writeSSHRecord,
  readHostList,
  writeHostList,
  readKey,
  writeKey,
  readSupportEmailList,
  readUserEmailList,
  writeUserEmailList,
  readNotifyList,
  getNotifySwByType,
  writeNotifyList,
  readGroupList,
  writeGroupList
}