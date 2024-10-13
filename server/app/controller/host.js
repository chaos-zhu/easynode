const { readHostList, writeHostList } = require('../utils/storage')
const { RSADecryptSync, AESEncryptSync, AESDecryptSync } = require('../utils/encrypt')

async function getHostList({ res }) {
  // console.log('get-host-list')
  let data = await readHostList()
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  for (const item of data) {
    try {
      let { username, port, authType, _id: id, credential } = item
      // console.log('解密凭证title: ', credential)
      if (credential) credential = await AESDecryptSync(credential)
      const isConfig = Boolean(username && port && (item[authType]))
      Object.assign(item, { id, isConfig, password: '', privateKey: '', credential })
    } catch (error) {
      consola.error('getHostList error: ', error.message)
    }
  }
  res.success({ data })
}

async function addHost({
  res, request
}) {
  let {
    body: {
      name, host, index, expired, expiredNotify, group, consoleUrl, remark,
      port: newPort, clientPort, username, authType, password, privateKey, credential, command, tempKey
    }
  } = request
  // console.log(request)
  if (!host || !name) return res.fail({ msg: 'missing params: name or host' })
  let hostList = await readHostList()
  let record = {
    name, host, index, expired, expiredNotify, group, consoleUrl, remark,
    port: newPort, clientPort, username, authType, password, privateKey, credential, command
  }
  if (record[authType]) {
    const clearTempKey = await RSADecryptSync(tempKey)
    console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
    console.log(`${ authType }原密文: `, clearSSHKey)
    record[authType] = await AESEncryptSync(clearSSHKey)
    // console.log(`${ authType }__commonKey加密存储: `, record[authType])
  }
  hostList.push(record)
  await writeHostList(hostList)
  res.success()
}

async function updateHost({ res, request }) {
  let {
    body: {
      hosts,
      id,
      host: newHost, name: newName, index, oldHost, expired, expiredNotify, group, consoleUrl, remark,
      port, clientPort, username, authType, password, privateKey, credential, command, tempKey
    }
  } = request
  let isBatch = Array.isArray(hosts)
  if (isBatch) {
    if (!hosts.length) return res.fail({ msg: 'hosts为空' })
    let hostList = await readHostList()
    let newHostList = []
    for (let oldRecord of hostList) {
      let record = hosts.find(item => item.id === oldRecord._id)
      if (!record) {
        newHostList.push(oldRecord)
        continue
      }
      let { authType } = record
      // 如果存在原认证方式则保存下来
      if (!record[authType] && oldRecord[authType]) {
        record[authType] = oldRecord[authType]
      } else {
        const clearTempKey = await RSADecryptSync(record.tempKey)
        // console.log('批量解密tempKey:', clearTempKey)
        const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
        // console.log(`${ authType }原密文: `, clearSSHKey)
        record[authType] = await AESEncryptSync(clearSSHKey)
        // console.log(`${ authType }__commonKey加密存储: `, record[authType])
      }
      delete oldRecord.monitorData
      delete record.monitorData
      newHostList.push(Object.assign(oldRecord, record))
    }
    await writeHostList(newHostList)
    return res.success({ msg: '批量修改成功' })
  }
  if (!newHost || !newName || !oldHost) return res.fail({ msg: '参数错误' })

  let hostList = await readHostList()
  if (!hostList.some(({ host }) => host === oldHost)) return res.fail({ msg: `原实例[${ oldHost }]不存在,请尝试添加实例` })

  let record = {
    name: newName, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark,
    port, clientPort, username, authType, password, privateKey, credential, command
  }

  let idx = hostList.findIndex(({ _id }) => _id === id)
  const oldRecord = hostList[idx]
  // 如果存在原认证方式则保存下来
  if (!record[authType] && oldRecord[authType]) {
    record[authType] = oldRecord[authType]
  } else {
    const clearTempKey = await RSADecryptSync(tempKey)
    // console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
    // console.log(`${ authType }原密文: `, clearSSHKey)
    record[authType] = await AESEncryptSync(clearSSHKey)
    // console.log(`${ authType }__commonKey加密存储: `, record[authType])
  }
  hostList.splice(idx, 1, record)
  writeHostList(hostList)
  res.success()
}

async function removeHost({
  res, request
}) {
  let { body: { ids } } = request
  let hostList = await readHostList()
  if (!Array.isArray(ids)) return res.fail({ msg: '参数错误' })
  hostList = hostList.filter(({ id }) => !ids.includes(id))
  writeHostList(hostList)
  res.success({ data: '已移除' })
}

async function importHost({
  res, request
}) {
  let { body: { importHost, isEasyNodeJson = false } } = request
  if (!Array.isArray(importHost)) return res.fail({ msg: '参数错误' })
  let hostList = await readHostList()
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
  hostList.push(...newHostList)
  writeHostList(hostList)
  res.success({ data: { len: newHostList.length } })
}

module.exports = {
  getHostList,
  addHost,
  updateHost,
  removeHost,
  importHost
}
