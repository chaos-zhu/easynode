const { RSADecryptAsync, AESEncryptAsync, AESDecryptAsync } = require('../utils/encrypt')
const { HostListDB } = require('../utils/db-class')
const hostListDB = new HostListDB().getInstance()

async function getHostList({ res }) {
  // console.log('get-host-list')
  let data = await hostListDB.findAsync({})
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  for (const item of data) {
    try {
      let { username, port, authType, _id: id, credential } = item
      // console.log('解密凭证title: ', credential)
      if (credential) credential = await AESDecryptAsync(credential)
      const isConfig = Boolean(username && port && (item[authType]))
      Object.assign(item, { id, isConfig, password: '', privateKey: '', credential })
    } catch (error) {
      consola.error('getHostList error: ', error.message)
    }
  }
  res.success({ data })
}

async function addHost({ res, request }) {
  let {
    body: {
      name, host, index, expired, expiredNotify, group, consoleUrl, remark,
      port: newPort, clientPort, username, authType, password, privateKey, credential, command, tempKey
    }
  } = request
  // console.log(request)
  if (!host || !name) return res.fail({ msg: 'missing params: name or host' })
  let record = {
    name, host, index, expired, expiredNotify, group, consoleUrl, remark,
    port: newPort, clientPort, username, authType, password, privateKey, credential, command
  }
  if (record[authType]) {
    const clearTempKey = await RSADecryptAsync(tempKey)
    console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptAsync(record[authType], clearTempKey)
    console.log(`${ authType }原密文: `, clearSSHKey)
    record[authType] = await AESEncryptAsync(clearSSHKey)
    // console.log(`${ authType }__commonKey加密存储: `, record[authType])
  }
  await hostListDB.insertAsync(record)
  res.success()
}

async function updateHost({ res, request }) {
  let {
    body: {
      hosts,
      id,
      host: newHost, name: newName, index, oldHost, expired, expiredNotify, group, consoleUrl, remark,
      port, clientPort, username, authType, password, privateKey, credential, command, tempKey, jumpHosts = []
    }
  } = request
  let isBatch = Array.isArray(hosts)
  if (isBatch) {
    if (!hosts.length) return res.fail({ msg: 'hosts为空' })
    let hostList = await hostListDB.findAsync({})
    for (let oldRecord of hostList) {
      let target = hosts.find(item => item.id === oldRecord._id)
      if (!target) continue
      let { authType } = target
      // 如果存在原认证方式则保存下来
      if (!target[authType]) {
        target[authType] = oldRecord[authType]
      } else {
        const clearTempKey = await RSADecryptAsync(target.tempKey)
        // console.log('批量解密tempKey:', clearTempKey)
        const clearSSHKey = await AESDecryptAsync(target[authType], clearTempKey)
        // console.log(`${ authType }原密文: `, clearSSHKey)
        target[authType] = await AESEncryptAsync(clearSSHKey)
        // console.log(`${ authType }__commonKey加密存储: `, target[authType])
      }
      delete target.monitorData
      delete target.tempKey
      Object.assign(oldRecord, target)
      await hostListDB.updateAsync({ _id: oldRecord._id }, oldRecord)
    }
    return res.success({ msg: '批量修改成功' })
  }
  if (!newHost || !newName || !oldHost) return res.fail({ msg: '参数错误' })

  let updateRecord = {
    name: newName, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark,
    port, clientPort, username, authType, password, privateKey, credential, command, jumpHosts
  }

  let oldRecord = await hostListDB.findOneAsync({ _id: id })
  // 如果存在原认证方式则保存下来
  if (!updateRecord[authType] && oldRecord[authType]) {
    updateRecord[authType] = oldRecord[authType]
  } else {
    const clearTempKey = await RSADecryptAsync(tempKey)
    // console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptAsync(updateRecord[authType], clearTempKey)
    // console.log(`${ authType }原密文: `, clearSSHKey)
    updateRecord[authType] = await AESEncryptAsync(clearSSHKey)
    // console.log(`${ authType }__commonKey加密存储: `, updateRecord[authType])
  }
  await hostListDB.updateAsync({ _id: oldRecord._id }, updateRecord)
  res.success({ msg: '修改成功' })
}

async function removeHost({ res, request }) {
  let { body: { ids } } = request
  if (!Array.isArray(ids)) return res.fail({ msg: '参数错误' })
  const numRemoved = await hostListDB.removeAsync({ _id: { $in: ids } }, { multi: true })
  res.success({ data: `已移除,数量: ${ numRemoved }` })
}

async function importHost({ res, request }) {
  let { body: { importHost, isEasyNodeJson = false } } = request
  if (!Array.isArray(importHost)) return res.fail({ msg: '参数错误' })
  let hostList = await hostListDB.findAsync({})
  // 考虑到批量导入可能会重复太多,先过滤已存在的host:port
  let hostListSet = new Set(hostList.map(({ host, port }) => `${ host }:${ port }`))
  let newHostList = importHost.filter(({ host, port }) => !hostListSet.has(`${ host }:${ port }`))
  let newHostListLen = newHostList.length
  if (newHostListLen === 0) return res.fail({ msg: '导入的实例已存在' })

  if (isEasyNodeJson) {
    newHostList = newHostList.map((item) => {
      item.credential = ''
      item.isConfig = false
      delete item.id
      delete item.isConfig
      return item
    })
  } else {
    let extraFiels = {
      expired: null, expiredNotify: false, group: 'default', consoleUrl: '', remark: '',
      authType: 'privateKey', password: '', privateKey: '', credential: '', command: ''
    }
    newHostList = newHostList.map((item, index) => {
      item.port = Number(item.port) || 0
      item.index = newHostListLen - index
      return Object.assign(item, { ...extraFiels })
    })
  }
  await hostListDB.insertAsync(newHostList)
  res.success({ data: { len: newHostList.length } })
}

module.exports = {
  getHostList,
  addHost,
  updateHost,
  removeHost,
  importHost
}
