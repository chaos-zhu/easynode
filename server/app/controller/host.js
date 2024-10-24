const path = require('path')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { RSADecryptAsync, AESEncryptAsync, AESDecryptAsync } = require('../utils/encrypt')
const { HostListDB } = require('../utils/db-class')
const hostListDB = new HostListDB().getInstance()

async function getHostList({ res }) {
  let data = await hostListDB.findAsync({})
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  for (const item of data) {
    try {
      let { authType, _id: id, credential } = item
      if (credential) credential = await AESDecryptAsync(credential)
      const isConfig = Boolean(authType && item[authType])
      Object.assign(item, { id, isConfig, password: '', privateKey: '', credential })
    } catch (error) {
      consola.error('getHostList error: ', error.message)
    }
  }
  res.success({ data })
}

async function addHost({ res, request }) {
  let { body } = request
  if (!body.name || !body.host) return res.fail({ msg: 'missing params: name or host' })
  let newRecord = { ...body }
  const { authType, tempKey } = newRecord
  if (newRecord[authType] && tempKey) {
    const clearTempKey = await RSADecryptAsync(tempKey)
    const clearSSHKey = await AESDecryptAsync(newRecord[authType], clearTempKey)
    newRecord[authType] = await AESEncryptAsync(clearSSHKey)
  }
  await hostListDB.insertAsync(newRecord)
  res.success()
}

async function updateHost({ res, request }) {
  let {
    body
  } = request
  if (typeof body !== 'object') return res.fail({ msg: '参数错误' })
  const updateFiled = { ...body }
  const { id, authType, tempKey } = updateFiled
  if (authType && updateFiled[authType]) {
    const clearTempKey = await RSADecryptAsync(tempKey)
    const clearSSHKey = await AESDecryptAsync(updateFiled[authType], clearTempKey)
    updateFiled[authType] = await AESEncryptAsync(clearSSHKey)
    delete updateFiled.tempKey
  } else {
    delete updateFiled.authType
    delete updateFiled.password
    delete updateFiled.privateKey
    delete updateFiled.credential
  }
  console.log('updateFiled: ', updateFiled)
  await hostListDB.updateAsync({ _id: id }, { $set: { ...updateFiled } })
  res.success({ msg: '修改成功' })
}

async function batchUpdateHost({ res, request }) {
  let { updateHosts } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (updateHosts) {
    await updateHosts({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
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
  importHost,
  batchUpdateHost
}
