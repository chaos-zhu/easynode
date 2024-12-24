const path = require('path')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { sendServerChan, sendEmail } = require('../utils/notify')
const { NotifyConfigDB, NotifyDB } = require('../utils/db-class')
const notifyDB = new NotifyDB().getInstance()
const notifyConfigDB = new NotifyConfigDB().getInstance()

async function getNotifyConfig({ res }) {
  const data = await notifyConfigDB.findOneAsync({})
  return res.success({ data })
}

async function updateNotifyConfig({ res, request }) {
  let { body: { noticeConfig } } = request
  let { type } = noticeConfig
  try {
    // console.log('noticeConfig: ', noticeConfig[type])
    switch (type) {
      case 'sct':
        await sendServerChan(noticeConfig[type]['sendKey'], 'EasyNode通知测试', '这是一条测试通知')
        break
      case 'email':
        await sendEmail(noticeConfig[type], 'EasyNode通知测试', '这是一条测试通知')
        break
      case 'tg':
        let { sendTg } = await decryptAndExecuteAsync(path.join(__dirname, '../utils/plus.js')) || {}
        console.log('sendTg: ', sendTg)
        if (!sendTg) return res.fail({ msg: 'Plus专属功能点，请激活Plus' })
        await sendTg(noticeConfig[type], 'EasyNode通知测试', '这是一条测试通知')
        break
    }
    await notifyConfigDB.update({}, { $set: noticeConfig }, { upsert: true })
    return res.success({ msg: '测试通过 | 保存成功' })
  } catch (error) {
    return res.fail({ msg: error.message })
  }
}

async function getNotifyList({ res }) {
  const data = await notifyDB.findAsync({})
  res.success({ data })
}

async function updateNotifyList({ res, request }) {
  let { body: { type, sw } } = request
  if (!([true, false].includes(sw))) return res.fail({ msg: `Error type for sw：${ sw }, must be Boolean` })
  await notifyDB.updateAsync({ type }, { $set: { sw } })
  res.success()
}

module.exports = {
  getNotifyConfig,
  updateNotifyConfig,
  getNotifyList,
  updateNotifyList
}
