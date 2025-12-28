const nodemailer = require('nodemailer')
const TelegramBot = require('node-telegram-bot-api')
const axios = require('axios')
const FormData = require('form-data')
const commonTemp = require('../template/commonTemp')
const { NotifyDB, NotifyConfigDB } = require('./db-class')
const notifyConfigDB = new NotifyConfigDB().getInstance()
const notifyDB = new NotifyDB().getInstance()

async function sendWebhook({ url, method = 'POST', contentType = 'application/json', headers = '', template = '' }, title, content) {
  return new Promise((async (resolve, reject) => {
    try {
      logger.info('Webhook通知预发送: ', title)

      const timestamp = Date.now()
      const datetime = new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })

      // JSON 字符串转义函数（用于在 JSON 字符串中安全替换变量）
      const escapeJsonString = (str) => {
        if (typeof str !== 'string') return str
        return str
          .replace(/\\/g, '\\\\')
          .replace(/"/g, '\\"')
          .replace(/\n/g, '\\n')
          .replace(/\r/g, '\\r')
          .replace(/\t/g, '\\t')
      }

      // 变量替换函数
      const replaceVars = (str, escapeForJson = false) => {
        const t = escapeForJson ? escapeJsonString(title) : title
        const c = escapeForJson ? escapeJsonString(content) : content
        const dt = escapeForJson ? escapeJsonString(datetime) : datetime
        return str
          .replace(/\{\{title\}\}/g, t)
          .replace(/\{\{content\}\}/g, c)
          .replace(/\{\{timestamp\}\}/g, timestamp)
          .replace(/\{\{datetime\}\}/g, dt)
      }

      // 构建请求数据
      let data
      const defaultData = { title, content, timestamp, datetime }

      if (template) {
        // JSON 类型需要转义特殊字符
        const needEscape = contentType === 'application/json'
        const replacedTemplate = replaceVars(template, needEscape)
        if (contentType === 'application/json') {
          try {
            data = JSON.parse(replacedTemplate)
          } catch (e) {
            logger.warn('Webhook模板JSON解析失败，使用原始字符串: ', e.message)
            data = replacedTemplate
          }
        } else {
          data = replacedTemplate
        }
      } else {
        data = defaultData
      }

      // 解析自定义请求头
      let customHeaders = {}
      if (headers) {
        try {
          customHeaders = JSON.parse(headers)
        } catch (e) {
          logger.warn('Webhook自定义请求头解析失败: ', e.message)
        }
      }

      // 构建请求配置
      const config = {
        method: method.toUpperCase(),
        url,
        headers: { ...customHeaders }
      }

      // 根据 Content-Type 处理请求数据
      if (method.toUpperCase() === 'GET') {
        config.params = typeof data === 'object' ? data : { data }
      } else {
        switch (contentType) {
          case 'application/json':
            config.headers['Content-Type'] = 'application/json'
            config.data = typeof data === 'object' ? data : JSON.parse(data)
            break
          case 'application/x-www-form-urlencoded':
            config.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            if (typeof data === 'object') {
              config.data = new URLSearchParams(data).toString()
            } else {
              config.data = data
            }
            break
          case 'multipart/form-data':
            const formData = new FormData()
            if (typeof data === 'object') {
              Object.keys(data).forEach(key => {
                formData.append(key, String(data[key]))
              })
            } else {
              formData.append('data', data)
            }
            config.data = formData
            config.headers = { ...config.headers, ...formData.getHeaders() }
            break
          case 'text/plain':
            config.headers['Content-Type'] = 'text/plain'
            config.data = typeof data === 'object' ? JSON.stringify(data) : data
            break
          default:
            config.headers['Content-Type'] = contentType
            config.data = data
        }
      }

      const response = await axios(config)
      logger.info('Webhook通知发送成功: ', title, response.status)
      resolve(response.data)
    } catch (error) {
      logger.error('Webhook通知发送失败: ', error.message)
      reject(error)
    }
  }))
}

async function sendServerChan(sendKey, title, content) {
  return new Promise((async (resolve, reject) => {
    try {
      logger.info('server酱通知预发送: ', title)
      const url = `https://sctapi.ftqq.com/${ sendKey }.send`
      const params = new URLSearchParams({ text: title, desp: content })
      let { data } = await axios.post(url, params, {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      })
      resolve(data)
      logger.info('server酱通知发送成功: ', title)
    } catch (error) {
      reject(error)
      logger.error('server酱通知发送失败: ', error)
    }
  }))

}

async function sendEmail({ service, user, pass, useCustom, host, port, secure, to }, title, content) {
  return new Promise((async (resolve, reject) => {
    try {
      logger.info('邮箱通知预发送: ', title)

      let transportConfig
      if (useCustom && host) {
        // 自定义 SMTP 模式
        transportConfig = {
          host,
          port: port || 465,
          secure: secure !== false, // 默认 true
          auth: { user, pass }
        }
        logger.info('使用自定义 SMTP 配置: ', { host, port, secure })
      } else {
        // 服务商模式（现有逻辑）
        transportConfig = {
          service,
          auth: { user, pass }
        }
        logger.info('使用服务商模式: ', service)
      }

      let transporter = nodemailer.createTransport(transportConfig)
      await transporter.sendMail({
        from: user,
        to: to || user, // 支持自定义收件人，留空则发送给自己
        subject: title,
        // text: '', // 纯文本版本内容，如果收件人的邮件客户端不支持HTML显示，就会显示这个文本
        html: commonTemp(content)
      })
      logger.info('邮件通知发送成功: ', title)
      resolve()
    } catch (error) {
      reject(error)
      logger.error('邮件通知发送失败: ', error)
    }
  }))
}

async function sendTg({ token, chatId }, title, content) {
  return new Promise((async (resolve, reject) => {
    try {
      logger.info('Telegram通知预发送: ', title)
      const bot = new TelegramBot(token)
      let msg = `*${ title }*\n${ content }`
      await bot.sendMessage(Number(chatId), msg, { parse_mode: 'Markdown' })
      logger.info('Telegram通知发送成功: ', title)
      resolve()
    } catch (error) {
      reject(error)
      logger.error('Telegram通知发送失败: ', error)
    }
  }))
}

// 异步发送通知
async function sendNoticeAsync(noticeAction, title, content) {
  try {
    let notifyList = await notifyDB.findAsync({})
    let { sw } = notifyList.find((item) => item.type === noticeAction) // 获取对应动作的通知开关
    // console.log('notify swtich: ', noticeAction, sw)
    if (!sw) return logger.info('通知开关关闭, 不发送通知: ', noticeAction)
    let notifyConfig = await notifyConfigDB.findOneAsync({})
    let { type } = notifyConfig
    if (!type) return logger.error('通知类型不存在: ', type)
    title = `EasyNode-${ title }`
    content += `\n通知发送时间：${ new Date() }`
    switch (type) {
      case 'sct':
        let { sendKey } = notifyConfig['sct']
        if (!sendKey) return logger.info('未发送server酱通知, sendKey 为空')
        await sendServerChan(sendKey, title, content)
        break
      case 'email':
        let { service, user, pass, useCustom, host, port, secure, to } = notifyConfig['email']
        // 自定义模式需要 host，服务商模式需要 service
        if (useCustom) {
          if (!host || !user || !pass) return logger.info('未发送邮件通知, 未配置自定义SMTP: ', { host, user, pass })
        } else {
          if (!service || !user || !pass) return logger.info('未发送邮件通知, 未配置邮箱: ', { service, user, pass })
        }
        await sendEmail({ service, user, pass, useCustom, host, port, secure, to }, title, content)
        break
      case 'tg':
        let { token, chatId } = notifyConfig['tg']
        if (!token || !chatId) return logger.info('未发送Telegram通知, 未配置token或chatId: ', { token, chatId })
        await sendTg({ token, chatId }, title, content)
        break
      case 'webhook':
        let { url, method, contentType, headers, template } = notifyConfig['webhook']
        if (!url) return logger.info('未发送Webhook通知, URL为空')
        await sendWebhook({ url, method, contentType, headers, template }, title, content)
        break
      default:
        logger.info('未配置通知类型: ', type)
        break
    }
  } catch (error) {
    logger.error('通知发送失败: ', error)
  }
}

module.exports = {
  sendNoticeAsync,
  sendServerChan,
  sendEmail,
  sendTg,
  sendWebhook
}