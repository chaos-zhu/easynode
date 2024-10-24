const path = require('path')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { randomStr } = require('../utils/tools')
const { ScriptsDB } = require('../utils/db-class')
const localShellJson = require('../config/shell.json')
const scriptsDB = new ScriptsDB().getInstance()

let localShell = JSON.parse(JSON.stringify(localShellJson)).map((item) => {
  return { ...item, id: randomStr(10), index: '--', description: item.description + '|内置脚本' }
})

async function getScriptList({ res }) {
  let data = await scriptsDB.findAsync({})
  data = data.map(item => {
    return { ...item, id: item._id }
  })
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  data.push(...localShell)
  res.success({ data })
}

async function getLocalScriptList({ res }) {
  res.success({ data: localShell })
}

const addScript = async ({ res, request }) => {
  let { body: { name, description, command, index } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  index = Number(index) || 0
  let record = { name, description, command, index }
  await scriptsDB.insertAsync(record)
  res.success({ data: '添加成功' })
}

const updateScriptList = async ({ res, request }) => {
  let { params: { id } } = request
  let { body: { name, description, command, index } } = request
  if (!name || !command) return res.fail({ data: false, msg: '参数错误' })
  await scriptsDB.updateAsync({ _id: id }, { name, description, command, index })
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
  let { impScript } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (impScript) {
    await impScript({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

module.exports = {
  addScript,
  getScriptList,
  getLocalScriptList,
  updateScriptList,
  removeScript,
  batchRemoveScript,
  importScript
}
