import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import decryptAndExecuteAsync from '../utils/decrypt-file.js'
import { ScriptsDB } from '../utils/db-class.js'
import { listBuiltinScripts } from '../services/script-library.js'
import {
  addItemsToOrder,
  moveItemsToGroup,
  ORDER_DOMAIN,
  removeItemsFromOrder
} from '../services/order-service.js'
import { disableScheduledTasksForScripts } from '../services/scheduled-task-service.js'
const scriptsDB = new ScriptsDB().getInstance()
const currentDir = dirname(fileURLToPath(import.meta.url))

async function getLocalScriptList({ res }) {
  res.success({ data: listBuiltinScripts() })
}

const addScript = async ({ res, request }) => {
  // useBase64 默认为false
  let { body: { name, description, command, group, useBase64 = false } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  let record = { name, description, command, group, useBase64 }
  const inserted = await scriptsDB.insertAsync(record)
  await addItemsToOrder(ORDER_DOMAIN.SCRIPTS, inserted)
  res.success({ data: '添加成功' })
}

const updateScriptList = async ({ res, request }) => {
  let { params: { id } } = request
  // useBase64 默认为false
  let { body: { name, description, command, group, useBase64 = false } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  const oldRecord = await scriptsDB.findOneAsync({ _id: id })
  if (!oldRecord) return res.fail({ data: false, msg: '脚本不存在' })
  await scriptsDB.updateAsync({ _id: id }, { name, description, command, group, useBase64 })
  if (group && group !== oldRecord.group) await moveItemsToGroup(ORDER_DOMAIN.SCRIPTS, [id], group)
  res.success({ data: '修改成功' })
}

const removeScript = async ({ res, request }) => {
  let { params: { id } } = request
  await scriptsDB.removeAsync({ _id: id })
  await removeItemsFromOrder(ORDER_DOMAIN.SCRIPTS, [id])
  try {
    await disableScheduledTasksForScripts([id])
  } catch (error) {
    logger.error('移除脚本后的定时任务禁用失败:', error)
  }
  res.success({ data: '移除成功' })
}

const batchRemoveScript = async ({ res, request }) => {
  let { body: { ids } } = request
  if (!Array.isArray(ids)) return res.fail({ msg: '参数错误' })
  const numRemoved = await scriptsDB.removeAsync({ _id: { $in: ids } }, { multi: true })
  await removeItemsFromOrder(ORDER_DOMAIN.SCRIPTS, ids)
  try {
    await disableScheduledTasksForScripts(ids)
  } catch (error) {
    logger.error('批量移除脚本后的定时任务禁用失败:', error)
  }
  res.success({ data: `批量移除成功,数量: ${ numRemoved }` })
}

const importScript = async ({ res, request }) => {
  let { impScript } = (await decryptAndExecuteAsync(path.join(currentDir, 'plus.js'))) || {}
  if (impScript) {
    await impScript({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

export {
  addScript,
  getLocalScriptList,
  updateScriptList,
  removeScript,
  batchRemoveScript,
  importScript
}
