const { HostListDB, GroupDB } = require('../utils/db-class')

const hostListDB = new HostListDB().getInstance()
const groupDB = new GroupDB().getInstance()

async function getGroupList({ res }) {
  let data = await groupDB.findAsync({})
  data = data.map(item => ({ ...item, id: item._id }))
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

const addGroupList = async ({ res, request }) => {
  let { body: { name, index } } = request
  if (!name) return res.fail({ data: false, msg: '参数错误' })
  let group = { name, index }
  await groupDB.insertAsync(group)
  res.success({ data: '添加成功' })
}

const updateGroupList = async ({ res, request }) => {
  let { params: { id } } = request
  let { body: { name, index } } = request
  if (!id || !name) return res.fail({ data: false, msg: '参数错误' })
  let target = await groupDB.findOneAsync({ _id: id })
  if (!target) return res.fail({ data: false, msg: `分组ID${ id }不存在` })
  await groupDB.updateAsync({ _id: id }, { name, index: Number(index) || 0 })
  res.success({ data: '修改成功' })
}

const removeGroup = async ({ res, request }) => {
  let { params: { id } } = request
  if (id === 'default') return res.fail({ data: false, msg: '保留分组, 禁止删除' })
  // 移除分组将所有该分组下host分配到default中去
  let hostList = await hostListDB.findAsync({})
  if (Array.isArray(hostList) && hostList.length > 0) {
    for (let item of hostList) {
      if (item.group === id) {
        item.group = 'default'
        await hostListDB.updateAsync({ _id: item._id }, item)
      }
    }
  }
  await groupDB.removeAsync({ _id: id })
  res.success({ data: '移除成功' })
}

module.exports = {
  addGroupList,
  getGroupList,
  updateGroupList,
  removeGroup
}
