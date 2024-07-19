const { readHostList, writeHostList, readSSHRecord, writeSSHRecord } = require('../utils')

async function getHostList({ res }) {
  // console.log('get-host-list')
  const data = await readHostList()
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

async function saveHost({ res, request }) {
  let { body: { host: newHost, name, index, expired, expiredNotify, group, consoleUrl, remark } } = request
  // console.log(request)
  if (!newHost || !name) return res.fail({ msg: 'missing params: name or host' })
  let hostList = await readHostList()
  if (hostList?.some(({ host }) => host === newHost)) return res.fail({ msg: `主机${ newHost }已存在` })
  if (!Array.isArray(hostList)) hostList = []
  hostList.push({ host: newHost, name, index, expired, expiredNotify, group, consoleUrl, remark })
  await writeHostList(hostList)
  res.success()
}

async function updateHost({ res, request }) {
  let { body: { host: newHost, name: newName, index, oldHost, expired, expiredNotify, group, consoleUrl, remark } } = request
  if (!newHost || !newName || !oldHost) return res.fail({ msg: '参数错误' })
  let hostList = await readHostList()
  if (!hostList.some(({ host }) => host === oldHost)) return res.fail({ msg: `主机${ newHost }不存在` })
  let targetIdx = hostList.findIndex(({ host }) => host === oldHost)
  hostList.splice(targetIdx, 1, { name: newName, host: newHost, index, expired, expiredNotify, group, consoleUrl, remark })
  writeHostList(hostList)
  res.success()
}

async function removeHost({ res, request }) {
  let { body: { host } } = request
  let hostList = await readHostList()
  let hostIdx = hostList.findIndex(item => item.host === host)
  if (hostIdx === -1) return res.fail({ msg: `${ host }不存在` })
  hostList.splice(hostIdx, 1)
  writeHostList(hostList)
  // 查询是否存在ssh记录
  let sshRecord = await readSSHRecord()
  let sshIdx = sshRecord.findIndex(item => item.host === host)
  let flag = sshIdx !== -1
  if (flag) sshRecord.splice(sshIdx, 1)
  writeSSHRecord(sshRecord)

  res.success({ data: `${ host }已移除, ${ flag ? '并移除ssh记录' : '' }` })
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
  saveHost,
  updateHost,
  removeHost
  // updateHostSort
}
