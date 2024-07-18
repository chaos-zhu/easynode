const schedule = require('node-schedule')
const { readHostList, sendEmailToConfList, formatTimestamp } = require('../utils')

const expiredNotifyJob = async () => {
  consola.info('=====开始检测服务器到期时间=====', new Date())
  const hostList = await readHostList()
  for (const item of hostList) {
    if(!item.expiredNotify) continue
    const { host, name, expired, consoleUrl } = item
    const restDay = Number(((expired - Date.now()) / (1000 * 60 * 60 * 24)).toFixed(1))
    console.log(Date.now(), restDay)
    let title = '服务器到期提醒'
    let content = `别名: ${ name }<br/>IP: ${ host }<br/>到期时间：${ formatTimestamp(expired, 'week') }<br/>控制台: ${ consoleUrl || '未填写' }`
    if(0 <= restDay && restDay <= 1) {
      let temp = '有服务器将在一天后到期，请关注<br/>'
      sendEmailToConfList(title, temp + content)
    }else if(3 <= restDay && restDay < 4) {
      let temp = '有服务器将在三天后到期，请关注<br/>'
      sendEmailToConfList(title, temp + content)
    }else if(7 <= restDay && restDay < 8) {
      let temp = '有服务器将在七天后到期，请关注<br/>'
      sendEmailToConfList(title, temp + content)
    }
  }
}

module.exports = () => {
  // 每天中午12点执行一次。
  schedule.scheduleJob('0 0 12 1/1 * ?', expiredNotifyJob)
}
