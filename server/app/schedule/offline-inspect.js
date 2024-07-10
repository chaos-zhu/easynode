const schedule = require('node-schedule')
const { clientPort } = require('../config')
const { readHostList, sendEmailToConfList, getNotifySwByType, formatTimestamp, isProd } = require('../utils')
const testConnectAsync = require('../utils/test-connect')

let sendNotifyRecord = new Map()
const offlineJob = async () => {
  let sw = getNotifySwByType('host_offline')
  if(!sw) return
  consola.info('=====开始检测服务器状态=====', new Date())
  const hostList = await readHostList()
  for (const item of hostList) {
    const { host, name } = item
    // consola.info('start inpect:', host, name )
    testConnectAsync({
      port: clientPort ,
      host: `http://${ host }`,
      timeout: 3000,
      retryTimes: 20 // 尝试重连次数
    })
      .then(() => {
        // consola.success('测试连接成功:', host, name)
      })
      .catch((error) => {
        consola.error('测试连接失败: ', host, name)
        // 当前小时是否发送过通知
        let curHourIsSend = sendNotifyRecord.has(host) && (sendNotifyRecord.get(host).sendTime === formatTimestamp(Date.now(), 'hour'))
        if(curHourIsSend) return consola.info('当前小时已发送过通知: ', sendNotifyRecord.get(host).sendTime)
        sendEmailToConfList('服务器离线提醒', `别名: ${ name }<br/>IP: ${ host }<br/>错误信息：${ error.message }`)
          .then(() => {
            sendNotifyRecord.set(host, { 'sendTime': formatTimestamp(Date.now(), 'hour') })
          })
      })
  }
}

module.exports = () => {
  if(!isProd()) return consola.info('本地开发不检测服务器离线状态')
  schedule.scheduleJob('0 0/5 12 1/1 * ?', offlineJob)
}
