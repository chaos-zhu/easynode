import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import decryptAndExecuteAsync from '../utils/decrypt-file.js'
import { RSADecryptAsync, AESEncryptAsync, AESDecryptAsync } from '../utils/encrypt.js'
import { HostListDB } from '../utils/db-class.js'
import {
  addItemsToOrder,
  moveItemsToGroup,
  ORDER_DOMAIN,
  removeItemsFromOrder
} from '../services/order-service.js'
import { detachHostsFromScheduledTasks } from '../services/scheduled-task-service.js'
const hostListDB = new HostListDB().getInstance()
const currentDir = dirname(fileURLToPath(import.meta.url))

async function addHost({ res, request }) {
  let { body } = request
  if (!body.name || !body.host) return res.fail({ msg: 'missing params: name or host' })
  let newRecord = { ...body }
  delete newRecord.index
  delete newRecord.id
  delete newRecord._id
  const { authType, tempKey } = newRecord
  if (newRecord[authType] && tempKey) {
    const clearTempKey = await RSADecryptAsync(tempKey)
    const clearSSHKey = await AESDecryptAsync(newRecord[authType], clearTempKey)
    newRecord[authType] = await AESEncryptAsync(clearSSHKey)
  }
  const inserted = await hostListDB.insertAsync(newRecord)
  await addItemsToOrder(ORDER_DOMAIN.HOSTS, inserted)
  res.success()
}

async function updateHost({ res, request }) {
  let {
    body
  } = request
  if (typeof body !== 'object') return res.fail({ msg: '参数错误' })
  const updateFiled = { ...body }
  const { id, authType, tempKey } = updateFiled
  delete updateFiled.index
  delete updateFiled._id
  delete updateFiled.id
  const oldRecord = await hostListDB.findOneAsync({ _id: id })
  if (!oldRecord) return res.fail({ msg: '实例不存在' })
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
  // console.log('updateFiled: ', updateFiled)
  await hostListDB.updateAsync({ _id: id }, { $set: { ...updateFiled } })
  if (updateFiled.group && updateFiled.group !== oldRecord.group) {
    await moveItemsToGroup(ORDER_DOMAIN.HOSTS, [id], updateFiled.group)
  }
  res.success({ msg: '修改成功' })
}

async function batchUpdateHost({ res, request }) {
  let { updateHosts } = (await decryptAndExecuteAsync(path.join(currentDir, 'plus.js'))) || {}
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
  await removeItemsFromOrder(ORDER_DOMAIN.HOSTS, ids)
  try {
    await detachHostsFromScheduledTasks(ids)
  } catch (error) {
    logger.error('移除主机后的定时任务解绑失败:', error)
  }
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
      const record = { ...item, credential: '' }
      delete record.id
      delete record._id
      delete record.isConfig
      delete record.index
      return record
    })
  } else {
    let extraFiels = {
      expired: null, expiredNotify: false, group: 'default', consoleUrl: '', tag: [],
      authType: 'privateKey', password: '', privateKey: '', credential: '', command: '',
      proxyType: '', jumpHosts: [], proxyServer: ''
    }
    newHostList = newHostList.map(item => {
      const record = { ...item, port: Number(item.port) || 0 }
      delete record.index
      return Object.assign(record, { ...extraFiels })
    })
  }
  const inserted = await hostListDB.insertAsync(newHostList)
  await addItemsToOrder(ORDER_DOMAIN.HOSTS, inserted)
  res.success({ data: { len: newHostList.length } })
}

async function updateLastConnectTime({ res, request }) {
  let { body: { id } } = request
  if (!id) return res.fail({ msg: '参数错误：缺少id' })

  try {
    const timestamp = Date.now()
    await hostListDB.updateAsync({ _id: id }, { $set: { lastConnectTime: timestamp } })
    res.success({ msg: '更新成功' })
  } catch (error) {
    logger.error('updateLastConnectTime error: ', error.message)
    res.fail({ msg: '更新失败' })
  }
}

export {
  addHost,
  updateHost,
  removeHost,
  importHost,
  batchUpdateHost,
  updateLastConnectTime
}
