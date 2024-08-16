const { readNotifyConfig, writeNotifyConfig, readNotifyList, writeNotifyList } = require('../utils')
const { sctTest, emailTest } = require('../utils/notify')
// const commonTemp = require('../template/commonTemp')

async function getNotifyConfig({ res }) {
  const data = await readNotifyConfig()
  return res.success({ data })
}

async function updateNotifyConfig({ res, request }) {
  let { body: { noticeConfig } } = request
  let { type } = noticeConfig
  try {
    switch(type) {
      case 'sct':
        await sctTest(noticeConfig[type])
        break
      case 'email':
        await emailTest(noticeConfig[type])
        break
    }
    await writeNotifyConfig(noticeConfig)
    return res.success({ msg: '测试通过 | 保存成功' })
  } catch (error) {
    return res.fail({ msg: error.message })
  }
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
