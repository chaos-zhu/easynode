const { readScriptList, writeScriptList } = require('../utils')

async function getScriptList({ res }) {
  let data = await readScriptList()
  data = data.map(item => {
    return { ...item, id: item._id }
  })
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

const addScript = async ({ res, request }) => {
  let { body: { name, remark, content, index } } = request
  if (!name || !content) return res.fail({ data: false, msg: '参数错误' })
  index = Number(index) || 0
  let scriptsList = await readScriptList()
  let record = { name, remark, content, index }
  scriptsList.push(record)
  await writeScriptList(scriptsList)
  res.success({ data: '添加成功' })
}

const updateScriptList = async ({ res, request }) => {
  let { params: { id } } = request
  let { body: { name, remark, content, index } } = request
  if (!name || !content) return res.fail({ data: false, msg: '参数错误' })
  let scriptsList = await readScriptList()
  let idx = scriptsList.findIndex(item => item._id === id)
  if (idx === -1) return res.fail({ data: false, msg: `脚本ID${ id }不存在` })
  const { _id } = scriptsList[idx]
  let record = Object.assign({ _id }, { name, remark, content, index })
  scriptsList.splice(idx, 1, record)
  await writeScriptList(scriptsList)
  res.success({ data: '修改成功' })
}

const removeScript = async ({ res, request }) => {
  let { params: { id } } = request
  let scriptsList = await readScriptList()
  let idx = scriptsList.findIndex(item => item._id === id)
  if (idx === -1) return res.fail({ msg: '脚本ID不存在' })
  scriptsList.splice(idx, 1)
  await writeScriptList(scriptsList)
  res.success({ data: '移除成功' })
}

module.exports = {
  addScript,
  getScriptList,
  updateScriptList,
  removeScript
}
