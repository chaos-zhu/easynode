const { readGroupList, writeGroupList, readHostList, writeHostList, randomStr } = require('../utils')

async function getGroupList({ res }) {
  let data = await readGroupList()
  data = data.map(item => {
    return { ...item, id: item._id }
  })
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

const addGroupList = async ({ res, request }) => {
  let { body: { name, index } } = request
  if (!name) return res.fail({ data: false, msg: '参数错误' })
  let groupList = await readGroupList()
  let group = { name, index }
  groupList.push(group)
  await writeGroupList(groupList)
  res.success({ data: '添加成功' })
}

const updateGroupList = async ({ res, request }) => {
  let { params: { id } } = request
  let { body: { name, index } } = request
  if (!id || !name) return res.fail({ data: false, msg: '参数错误' })
  let groupList = await readGroupList()
  let idx = groupList.findIndex(item => item._id === id)
  if (idx === -1) return res.fail({ data: false, msg: `分组ID${ id }不存在` })
  const { _id } = groupList[idx]
  let group = { _id, name, index: Number(index) || 0 }
  groupList.splice(idx, 1, group)
  await writeGroupList(groupList)
  res.success({ data: '修改成功' })
}

const removeGroup = async ({ res, request }) => {
  let { params: { id } } = request
  if (id === 'default') return res.fail({ data: false, msg: '保留分组, 禁止删除' })
  let groupList = await readGroupList()
  let idx = groupList.findIndex(item => item._id === id)
  if (idx === -1) return res.fail({ msg: '分组不存在' })

  // 移除分组将所有该分组下host分配到default中去
  let hostList = await readHostList()
  hostList = hostList?.map((item) => {
    if (item.group === groupList[idx]._id) item.group = 'default'
    return item
  })
  await writeHostList(hostList)

  groupList.splice(idx, 1)
  await writeGroupList(groupList)

  res.success({ data: '移除成功' })
}

module.exports = {
  addGroupList,
  getGroupList,
  updateGroupList,
  removeGroup
}
