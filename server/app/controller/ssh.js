const path = require('path')
const { RSADecryptAsync, AESEncryptAsync, AESDecryptAsync } = require('../utils/encrypt')
const { HostListDB, CredentialsDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const hostListDB = new HostListDB().getInstance()
const credentialsDB = new CredentialsDB().getInstance()

async function getSSHList({ res }) {
  let data = await credentialsDB.findAsync({})
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
  if (!name || !record[authType]) return res.fail({ data: false, msg: '参数错误' })
  let count = await credentialsDB.countAsync({ name })
  if (count > 0) return res.fail({ data: false, msg: '已存在同名凭证' })

  const clearTempKey = await RSADecryptAsync(tempKey)
  console.log('clearTempKey:', clearTempKey)
  const clearSSHKey = await AESDecryptAsync(record[authType], clearTempKey)
  // console.log(`${ authType }原密文: `, clearSSHKey)
  record[authType] = await AESEncryptAsync(clearSSHKey)
  // console.log(`${ authType }__commonKey加密存储: `, record[authType])
  await credentialsDB.insertAsync({ ...record, date: Date.now() })
  consola.info('添加凭证：', name)
  res.success({ data: '保存成功' })
}

const updateSSH = async ({ res, request }) => {
  let { body: { id, name, authType, password, privateKey, date, tempKey } } = request
  let record = { name, authType, password, privateKey, date }
  if (!id || !name) return res.fail({ data: false, msg: '请输入凭据名称' })
  let oldRecord = await credentialsDB.findOneAsync({ _id: id })
  if (!oldRecord) return res.fail({ data: false, msg: '凭证不存在' })
  // 判断原记录是否存在当前更新记录的认证方式
  if (!oldRecord[authType] && !record[authType]) return res.fail({ data: false, msg: `请输入${ authType === 'password' ? '密码' : '密钥' }` })
  if (!record[authType] && oldRecord[authType]) {
    record[authType] = oldRecord[authType]
  } else {
    const clearTempKey = await RSADecryptAsync(tempKey)
    console.log('clearTempKey:', clearTempKey)
    const clearSSHKey = await AESDecryptAsync(record[authType], clearTempKey)
    // console.log(`${ authType }原密文: `, clearSSHKey)
    record[authType] = await AESEncryptAsync(clearSSHKey)
    // console.log(`${ authType }__commonKey加密存储: `, record[authType])
  }
  await credentialsDB.updateAsync({ _id: id }, record)
  consola.info('修改凭证：', name)
  res.success({ data: '保存成功' })
}

const removeSSH = async ({ res, request }) => {
  let { params: { id } } = request
  let count = await credentialsDB.countAsync({ _id: id })
  if (count === 0) return res.fail({ msg: '凭证不存在' })
  // 将删除的凭证id从host中删除
  let hostList = await hostListDB.findAsync({})
  if (Array.isArray(hostList) && hostList.length > 0) {
    for (let host of hostList) {
      let { credential } = host
      credential = await AESDecryptAsync(credential)
      if (credential === id) {
        host.credential = ''
        await hostListDB.updateAsync({ _id: host._id }, host)
      }
    }
  }
  await hostListDB.compactDatafileAsync()
  consola.info('移除凭证：', id)
  await credentialsDB.removeAsync({ _id: id })
  res.success({ data: '移除成功' })
}

const getCommand = async ({ res, request }) => {
  let { hostId } = request.query
  if (!hostId) return res.fail({ data: false, msg: '参数错误' })
  let hostInfo = await hostListDB.findAsync({})
  let record = hostInfo?.find(item => item._id === hostId)
  consola.info('查询登录后执行的指令：', hostId)
  if (!record) return res.fail({ data: false, msg: 'host not found' })
  const { command } = record
  if (!command) return res.success({ data: false })
  res.success({ data: command })
}

const decryptPrivateKey = async ({ res, request }) => {
  let { dePrivateKey } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (dePrivateKey) {
    await dePrivateKey({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能，无法解密私钥!' })
  }
}

module.exports = {
  getSSHList,
  addSSH,
  updateSSH,
  removeSSH,
  getCommand,
  decryptPrivateKey
}
