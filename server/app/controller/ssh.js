const { readSSHRecord, writeSSHRecord, AESEncryptSync } = require('../utils')

const updateSSH = async ({ res, request }) => {
  let { body: { host, port, username, type, password, privateKey, randomKey, command } } = request
  let record = { host, port, username, type, password, privateKey, randomKey, command }
  if(!host || !port || !username || !type || !randomKey) return res.fail({ data: false, msg: '参数错误' })
  // 再做一次对称加密(方便ssh连接时解密)
  record.randomKey = await AESEncryptSync(randomKey)
  let sshRecord = await readSSHRecord()
  let idx = sshRecord.findIndex(item => item.host === host)
  if(idx === -1)
    sshRecord.push(record)
  else
    sshRecord.splice(idx, 1, record)
  await writeSSHRecord(sshRecord)
  consola.info('新增凭证：', host)
  res.success({ data: '保存成功' })
}

const removeSSH = async ({ res, request }) => {
  let { body: { host } } = request
  let sshRecord = await readSSHRecord()
  let idx = sshRecord.findIndex(item => item.host === host)
  if(idx === -1) return res.fail({ msg: '凭证不存在' })
  sshRecord.splice(idx, 1)
  consola.info('移除凭证：', host)
  await writeSSHRecord(sshRecord)
  res.success({ data: '移除成功' })
}

const existSSH = async ({ res, request }) => {
  let { body: { host } } = request
  let sshRecord = await readSSHRecord()
  let isExist = sshRecord?.some(item => item.host === host)
  consola.info('查询凭证：', host)
  if(!isExist) return res.success({ data: false }) // host不存在
  res.success({ data: true }) // 存在
}

const getCommand = async ({ res, request }) => {
  let { host } = request.query
  if(!host) return res.fail({ data: false, msg: '参数错误' })
  let sshRecord = await readSSHRecord()
  let record = sshRecord?.find(item => item.host === host)
  consola.info('查询登录后执行的指令：', host)
  if(!record) return res.fail({ data: false, msg: 'host not found' }) // host不存在
  const { command } = record
  if(!command) return res.success({ data: false }) // command不存在
  res.success({ data: command }) // 存在
}

module.exports = {
  updateSSH,
  removeSSH,
  existSSH,
  getCommand
}
