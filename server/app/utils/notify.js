const nodemailer = require('nodemailer')
const axios = require('axios')

module.exports.sctTest = function ({ sendKey }) {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise((async (resolve, reject) => {
    consola.info('server酱通知测试: ', sendKey)
    try {
      let { data } = await axios.get(`https://sctapi.ftqq.com/${ sendKey }.send?title=messagetitle`)
      resolve(data)
      consola.success('测试成功')
    } catch (error) {
      reject(error)
      consola.error('测试失败: ', error)
    }
  }))
}

module.exports.emailTest = function (conf) {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise((async (resolve, reject) => {
    consola.info('邮箱通知测试: ', conf)
    try {
      const { service, user, pass } = conf
      let transporter = nodemailer.createTransport({
        service,
        auth: {
          user,
          pass
        }
      })
      let info = await transporter.sendMail({
        from: user,
        to: user,
        subject: 'EasyNode: 测试邮件通知',
        text: '测试邮件',
        html: '<b>测试邮件</b>'
      })
      consola.info('Message sent: %s', info.messageId)
      resolve()
      consola.success('测试成功')
    } catch (error) {
      reject(error)
      consola.error('测试失败: ', error)
    }
  }))
}
