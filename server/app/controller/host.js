const { readHostList, writeHostList, RSADecryptSync, AESEncryptSync, AESDecryptSync } = require('../utils')

async function getHostList({ res }) {
  // console.log('get-host-list')
  let data = await readHostList()
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  data = data.map((item) => {
    const { username, port, authType, _id: id } = item
    const isConfig = Boolean(username && port && (item[authType]))
    return {
      ...item,
      id,
      isConfig,
      password: '',
      privateKey: ''
    }
  })
  res.success({ data })
}

async function addHost({
  res, request
}) {
  let {
    body: {
      name, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark,
      port, username, authType, password, privateKey, credential, command, tempKey
    }
  } = request
  // console.log(request)
  if (!newHost || !name) return res.fail({ msg: 'missing params: name or host' })
  let hostList = await readHostList()
  if (hostList?.some(({ host }) => host === newHost)) return res.fail({ msg: `主机${ newHost }已存在` })
  let record = {
    name, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark,
    port, username, authType, password, privateKey, credential, command
  }
  const clearTempKey = await RSADecryptSync(tempKey)
  console.log('clearTempKey:', clearTempKey)
  const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
  // console.log(`${ authType }原密文: `, clearSSHKey)
  record[authType] = await AESEncryptSync(clearSSHKey)
  console.log(`${ authType }__commonKey加密存储: `, record[authType])
  hostList.push(record)
  await writeHostList(hostList)
  res.success()
}

async function updateHost({
  res, request
}) {
  let {
    body: {
      host: newHost, name: newName, index, oldHost, expired, expiredNotify, group, consoleUrl, remark,
      port, username, authType, password, privateKey, credential, command, tempKey
    }
  } = request
  if (!newHost || !newName || !oldHost) return res.fail({ msg: '参数错误' })
  let hostList = await readHostList()
  let record = {
    name: newName, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark,
    port, username, authType, password, privateKey, credential, command
  }
  if (!hostList.some(({ host }) => host === oldHost)) return res.fail({ msg: `原实例[${ oldHost }]不存在,请尝试新增实例` })

  let idx = hostList.findIndex(({ host }) => host === oldHost)
  const oldRecord = hostList[idx]
  // 如果存在原认证方式则保存下来
  if (!record[authType] && oldRecord[authType]) {
    record[authType] = oldRecord[authType]
  } else {
    const clearTempKey = await RSADecryptSync(tempKey)
    console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
    // console.log(`${ authType }原密文: `, clearSSHKey)
    record[authType] = await AESEncryptSync(clearSSHKey)
    console.log(`${ authType }__commonKey加密存储: `, record[authType])
  }
  hostList.splice(idx, 1, record)
  writeHostList(hostList)
  res.success()
}

async function removeHost({
  res, request
}) {
  let { body: { host } } = request
  let hostList = await readHostList()
  let hostIdx = hostList.findIndex(item => item.host === host)
  if (hostIdx === -1) return res.fail({ msg: `${ host }不存在` })
  hostList.splice(hostIdx, 1)
  writeHostList(hostList)
  // 查询是否存在ssh记录
  // let sshRecord = await readSSHRecord()
  // let sshIdx = sshRecord.findIndex(item => item.host === host)
  // let flag = sshIdx !== -1
  // if (flag) sshRecord.splice(sshIdx, 1)
  // writeSSHRecord(sshRecord)

  // res.success({ data: `${ host }已移除, ${ flag ? '并移除ssh记录' : '' }` })
  res.success({ data: `${ host }已移除` })
}

// 原手动排序接口-废弃
// async function updateHostSort({ res, request }) {
//   let { body: { list } } = request
//   if (!list) return res.fail({ msg: '参数错误' })
//   let hostList = await readHostList()
//   if (hostList.length !== list.length) return res.fail({ msg: '失败: host数量不匹配' })
//   let sortResult = []
//   for (let i = 0; i < list.length; i++) {
//     const curHost = list[i]
//     let temp = hostList.find(({ host }) => curHost.host === host)
//     if (!temp) return res.fail({ msg: `查找失败: ${ curHost.name }` })
//     sortResult.push(temp)
//   }
//   writeHostList(sortResult)
//   res.success({ msg: 'success' })
// }

module.exports = {
  getHostList,
  addHost,
  updateHost,
  removeHost
  // updateHostSort
}
