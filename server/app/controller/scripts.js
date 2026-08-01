import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import decryptAndExecuteAsync from '../utils/decrypt-file.js'
import { ScriptsDB } from '../utils/db-class.js'
import { listBuiltinScripts, listScripts } from '../script-library.js'
const scriptsDB = new ScriptsDB().getInstance()
const currentDir = dirname(fileURLToPath(import.meta.url))

async function getScriptList({ res }) {
  res.success({ data: await listScripts() })
}

async function getLocalScriptList({ res }) {
  res.success({ data: listBuiltinScripts() })
}

const addScript = async ({ res, request }) => {
  // useBase64 默认为false
  let { body: { name, description, command, index, group, useBase64 = false } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  index = Number(index) || 0
  let record = { name, description, command, index, group, useBase64 }
  await scriptsDB.insertAsync(record)
  res.success({ data: '添加成功' })
}

const updateScriptList = async ({ res, request }) => {
  let { params: { id } } = request
  // useBase64 默认为false
  let { body: { name, description, command, index, group, useBase64 = false } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  await scriptsDB.updateAsync({ _id: id }, { name, description, command, index, group, useBase64 })
  res.success({ data: '修改成功' })
}

const removeScript = async ({ res, request }) => {
  let { params: { id } } = request
  await scriptsDB.removeAsync({ _id: id })
  res.success({ data: '移除成功' })
}

const batchRemoveScript = async ({ res, request }) => {
  let { body: { ids } } = request
  if (!Array.isArray(ids)) return res.fail({ msg: '参数错误' })
  const numRemoved = await scriptsDB.removeAsync({ _id: { $in: ids } }, { multi: true })
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
  getScriptList,
  getLocalScriptList,
  updateScriptList,
  removeScript,
  batchRemoveScript,
  importScript
}
