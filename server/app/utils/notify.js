const nodemailer = require('nodemailer')
const axios = require('axios')
const commonTemp = require('../template/commonTemp')
const { NotifyDB, NotifyConfigDB } = require('./db-class')
const notifyConfigDB = new NotifyConfigDB().getInstance()
const notifyDB = new NotifyDB().getInstance()

function sendServerChan(sendKey, title, content) {
  if (!sendKey) return consola.error('发送server酱通知失败, sendKey 为空')
  return new Promise((async (resolve, reject) => {
    try {
      consola.info('server酱通知预发送: ', title)
      const url = `https://sctapi.ftqq.com/${ sendKey }.send`
      const params = new URLSearchParams({ text: title, desp: content })
      let { data } = await axios.post(url, params, {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      })
      resolve(data)
      consola.info('server酱通知发送成功: ', title)
    } catch (error) {
      reject(error)
      consola.error('server酱通知发送失败: ', error)
    }
  }))

}

function sendEmail({ service, user, pass }, title, content) {
  if (!service || !user || !pass) return consola.info('发送通知失败, 邮箱配置信息不完整: ', { service, user, pass })
  return new Promise((async (resolve, reject) => {
    try {
      consola.info('邮箱通知预发送: ', title)
      let transporter = nodemailer.createTransport({
        service,
        auth: {
          user,
          pass
        }
      })
      await transporter.sendMail({
        from: user,
        to: user,
        subject: title,
        // text: '', // 纯文本版本内容，如果收件人的邮件客户端不支持HTML显示，就会显示这个文本
        html: commonTemp(content)
      })
      consola.info('邮件通知发送成功: ', title)
      resolve()
    } catch (error) {
      reject(error)
      consola.error('邮件通知发送失败: ', error)
    }
  }))
}

// 异步发送通知
async function sendNoticeAsync(noticeAction, title, content) {
  try {
    let notifyList = await notifyDB.findAsync({})
    let { sw } = notifyList.find((item) => item.type === noticeAction) // 获取对应动作的通知开关
    console.log('notify swtich: ', noticeAction, sw)
    if (!sw) return
    let notifyConfig = await notifyConfigDB.findOneAsync({})
    let { type } = notifyConfig
    if (!type) return consola.error('通知类型不存在: ', type)
    title = `EasyNode-${ title }`
    content += `\n通知发送时间：${ new Date() }`
    switch (type) {
      case 'sct':
        let { sendKey } = notifyConfig['sct']
        if (!sendKey) return consola.info('未发送server酱通知, sendKey 为空')
        await sendServerChan(sendKey, title, content)
        break
      case 'email':
        let { service, user, pass } = notifyConfig['email']
        if (!service || !user || !pass) return consola.info('未发送邮件通知通知, 未配置邮箱: ', { service, user, pass })
        await sendEmail({ service, user, pass }, title, content)
        break
      default:
        break
    }
  } catch (error) {
    consola.error('通知发送失败: ', error)
  }
}

module.exports = {
  sendNoticeAsync,
  sendServerChan,
  sendEmail
}