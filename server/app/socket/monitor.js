const { Server } = require('socket.io')
const schedule = require('node-schedule')
const axios = require('axios')
let getOsData = require('../utils/os-data')
const consola = require('consola')

let serverSockets = {}, ipInfo = {}, osData = {}

async function getIpInfo() {
  try {
    let { data } = await axios.get('http://ip-api.com/json?lang=zh-CN')
    consola.success('getIpInfo Success: ', new Date())
    ipInfo = data
  } catch (error) {
    consola.error('getIpInfo Error: ', new Date(), error)
  }
}

function ipSchedule() {
  let rule1 = new schedule.RecurrenceRule()
  rule1.second = [0, 10, 20, 30, 40, 50]
  schedule.scheduleJob(rule1, () => {
    let { query, country, city } = ipInfo || {}
    if(query && country && city) return
    consola.success('Task: start getIpInfo', new Date())
    getIpInfo()
  })

  // 每日凌晨两点整,刷新ip信息(兼容动态ip服务器)
  let rule2 = new schedule.RecurrenceRule()
  rule2.hour = 2
  rule2.minute = 0
  rule2.second = 0
  schedule.scheduleJob(rule2, () => {
    consola.info('Task: refresh ip info', new Date())
    getIpInfo()
  })
}

ipSchedule()

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/client/os-info',
    cors: {
      origin: '*'
    }
  })

  serverIo.on('connection', (socket) => {
    // 存储对应websocket连接的定时器
    serverSockets[socket.id] = setInterval(async () => {
      try {
        osData = await getOsData()
        socket && socket.emit('client_data', Object.assign(osData, { ipInfo }))
      } catch (error) {
        consola.error('客户端错误：', error)
        socket && socket.emit('client_error', { error })
      }
    }, 1000)

    socket.on('disconnect', () => {
      // 断开时清楚对应的websocket连接
      if(serverSockets[socket.id]) clearInterval(serverSockets[socket.id])
      delete serverSockets[socket.id]
      socket.close && socket.close()
      socket = null
      // console.log('断开socketId: ', socket.id, '剩余链接数: ', Object.keys(serverSockets).length)
    })
  })
}
