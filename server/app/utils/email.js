const nodemailer = require('nodemailer')
const { readSupportEmailList, readUserEmailList } = require('./storage')
const commonTemp = require('../template/commonTemp')

const emailCode = {
  SUCCESS: 0,
  FAIL: -1
}

const emailTransporter = async (params = {}) => {
  let { toEmail, title, html } = params
  try {
    if(!toEmail) throw Error('missing params: toEmail')
    let userEmail = readUserEmailList().find(({ auth }) => auth.user === toEmail)
    if(!userEmail) throw Error(`${ toEmail } 不存在已保存的配置文件中, 请移除后重新添加`)
    let { target } = userEmail
    let emailServerConf = readSupportEmailList().find((item) => item.target === target)
    if(!emailServerConf) throw Error(`邮箱类型不支持：${ target }`)
    const timeout = 1000*6
    let options = Object.assign({}, userEmail, emailServerConf, { greetingTimeout: timeout, connectionTimeout: timeout })
    let transporter = nodemailer.createTransport(options)
    let info = await transporter.sendMail({
      from: userEmail.auth.user, // sender address
      to: userEmail.auth.user, // list of receivers
      subject: `EasyNode: ${ title }`,
      html
    })
    // consola.success('email发送成功：', info.accepted)
    return { code: emailCode.SUCCESS, msg: `send successful：${ info.accepted }` }
  } catch(error) {
    // consola.error(`email发送失败(${ toEmail })：`, error.message || error)
    return { code: emailCode.FAIL, msg: error }
  }
}

const sendEmailToConfList = (title, content) => {
  // eslint-disable-next-line
  return new Promise(async (res, rej) => {
    let emailList = readUserEmailList()
    if(Array.isArray(emailList) && emailList.length >= 1) {
      for (const item of emailList) {
        const toEmail = item.auth.user
        await emailTransporter({ toEmail, title, html: commonTemp(content) })
          .then(({ code }) => {
            if(code === 0) {
              consola.success('已发送邮件通知: ', toEmail, title)
              return res({ code: emailCode.SUCCESS })
            }
            consola.error('邮件通知发送失败: ', toEmail, title)
            return rej({ code: emailCode.FAIL })
          })
      }
    }
  })
}

module.exports = {
  emailTransporter,
  sendEmailToConfList
}