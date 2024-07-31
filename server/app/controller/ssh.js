const { readSSHRecord, writeSSHRecord, readHostList, writeHostList, RSADecryptSync, AESEncryptSync, AESDecryptSync } = require('../utils')

async function getSSHList({ res }) {
  // console.log('get-host-list')
  let data = await readSSHRecord()
  data = data?.map(item => {
    const { name, authType, _id: id, date } = item
    return { id, name, authType, privateKey: '', password: '', date }
  }) || []
  data.sort((a, b) => b.date - a.date)
  res.success({ data })
}

const addSSH = async ({ res, request }) => {
  let { body: { name, authType, password, privateKey, tempKey } } = request
  let record = { name, authType, password, privateKey }
  if(!name || !record[authType]) return res.fail({ data: false, msg: '参数错误' })
  let sshRecord = await readSSHRecord()
  if (sshRecord.some(item => item.name === name)) return res.fail({ data: false, msg: '已存在同名凭证' })

  const clearTempKey = await RSADecryptSync(tempKey)
  console.log('clearTempKey:', clearTempKey)
  const clearSSHKey = await AESDecryptSync(record[authType], clearTempKey)
  // console.log(`${ authType }原密文: `, clearSSHKey)
  record[authType] = await AESEncryptSync(clearSSHKey)
  console.log(`${ authType }__commonKey加密存储: `, record[authType])

  sshRecord.push({ ...record, date: Date.now() })
  await writeSSHRecord(sshRecord)
  consola.info('添加凭证：', name)
  res.success({ data: '保存成功' })
}

const updateSSH = async ({ res, request }) => {
  let { body: { id, name, authType, password, privateKey, date, tempKey } } = request
  let record = { name, authType, password, privateKey, date }
  if(!id || !name) return res.fail({ data: false, msg: '请输入凭据名称' })
  let sshRecord = await readSSHRecord()
  let idx = sshRecord.findIndex(item => item._id === id)
  if (sshRecord.some(item => item.name === name && item.date !== date)) return res.fail({ data: false, msg: '已存在同名凭证' })
  if(idx === -1) res.fail({ data: false, msg: '请输入凭据名称' })
  const oldRecord = sshRecord[idx]
  // 判断原记录是否存在当前更新记录的认证方式
  if (!oldRecord[authType] && !record[authType]) return res.fail({ data: false, msg: `请输入${ authType === 'password' ? '密码' : '密钥' }` })
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
  record._id = sshRecord[idx]._id
  sshRecord.splice(idx, 1, record)
  await writeSSHRecord(sshRecord)
  consola.info('修改凭证：', name)
  res.success({ data: '保存成功' })
}

const removeSSH = async ({ res, request }) => {
  let { params: { id } } = request
  let sshRecord = await readSSHRecord()
  let idx = sshRecord.findIndex(item => item._id === id)
  if(idx === -1) return res.fail({ msg: '凭证不存在' })
  sshRecord.splice(idx, 1)
  // 将删除的凭证id从host中删除
  let hostList = await readHostList()
  hostList = hostList.map(item => {
    if (item.credential === id) item.credential = ''
    return item
  })
  await writeHostList(hostList)
  consola.info('移除凭证：', id)
  await writeSSHRecord(sshRecord)
  res.success({ data: '移除成功' })
}

const getCommand = async ({ res, request }) => {
  let { host } = request.query
  if(!host) return res.fail({ data: false, msg: '参数错误' })
  let hostInfo = await readHostList()
  let record = hostInfo?.find(item => item.host === host)
  consola.info('查询登录后执行的指令：', host)
  if(!record) return res.fail({ data: false, msg: 'host not found' }) // host不存在
  const { command } = record
  if(!command) return res.success({ data: false }) // command不存在
  res.success({ data: command }) // 存在
}

module.exports = {
  getSSHList,
  addSSH,
  updateSSH,
  removeSSH,
  getCommand
}
