const { readSSHRecord, writeSSHRecord } = require('../utils')

const updateSSH = async ({ res, request }) => {
  let { body: { host, port, username, type, password, privateKey, command } } = request
  let record = { host, port, username, type, password, privateKey, command }
  let sshRecord = readSSHRecord()
  let idx = sshRecord.findIndex(item => item.host === host)
  if(idx === -1)
    sshRecord.push(record)
  else
    sshRecord.splice(idx, 1, record)
  writeSSHRecord(sshRecord)
  res.success({ data: '保存成功' })
}

const removeSSH = async ({ res, request }) => {
  let { body: { host } } = request
  let sshRecord = readSSHRecord()
  let idx = sshRecord.findIndex(item => item.host === host)
  if(idx === -1) return res.fail({ msg: '凭证不存在' })
  sshRecord.splice(idx, 1)
  writeSSHRecord(sshRecord)
  res.success({ data: '移除成功' })
}

const existSSH = async ({ res, request }) => {
  let { body: { host } } = request
  let sshRecord = readSSHRecord()
  let idx = sshRecord.findIndex(item => item.host === host)
  if(idx === -1) return res.success({ data: false })
  res.success({ data: true })
}

const getCommand = async ({ res, request }) => {
  let { host } = request.query
  if(!host) return res.fail({ data: false, msg: '参数错误' })
  let sshRecord = readSSHRecord()
  let record = sshRecord.find(item => item.host === host)
  if(!record) return res.fail({ data: false, msg: 'host not found' })
  const { command } = record
  if(!command) return res.success({ data: false })
  res.success({ data: command })
}

module.exports = {
  updateSSH,
  removeSSH,
  existSSH,
  getCommand
}
