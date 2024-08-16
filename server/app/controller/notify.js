const { readNotifyConfig, writeNotifyConfig, readNotifyList, writeNotifyList } = require('../utils')
// const commonTemp = require('../template/commonTemp')

async function getNotifyConfig({ res }) {
  const data = await readNotifyConfig()
  return res.success({ data })
}

// 根据type待编写测试方法，测试通过才保存到库
async function updateNotifyConfig({ res, request }) {
  let { body: { noticeConfig } } = request
  await writeNotifyConfig(noticeConfig)
  return res.success()
}

async function getNotifyList({ res }) {
  const data = await readNotifyList()
  res.success({ data })
}

async function updateNotifyList({ res, request }) {
  let { body: { type, sw } } = request
  if (!([true, false].includes(sw))) return res.fail({ msg: `Error type for sw：${ sw }, must be Boolean` })
  const notifyList = await readNotifyList()
  let target = notifyList.find((item) => item.type === type)
  if (!target) return res.fail({ msg: `更新失败, 不存在该通知类型：${ type }` })
  target.sw = sw
  await writeNotifyList(notifyList)
  res.success()
}

module.exports = {
  getNotifyConfig,
  updateNotifyConfig,
  getNotifyList,
  updateNotifyList
}
