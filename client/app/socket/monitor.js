const { Server } = require('socket.io')
const schedule = require('node-schedule')
const axios = require('axios')
let getOsData = require('../utils/os-data')

let serverSockets = {}, ipInfo = {}, osData = {}

async function getIpInfo() {
  try {
    let { data } = await axios.get('http://ip-api.com/json?lang=zh-CN')
    console.log('getIpInfo Success: ', new Date())
    ipInfo = data
  } catch (error) {
    console.log('getIpInfo Error: ', new Date(), error)
  }
}

function ipSchedule() {
  let rule1 = new schedule.RecurrenceRule()
  rule1.second = [0, 10, 20, 30, 40, 50]
  schedule.scheduleJob(rule1, () => {
    let { query, country, city } = ipInfo || {}
    if(query && country && city) return
    console.log('Task: start getIpInfo', new Date())
    getIpInfo()
  })

  // 每日凌晨两点整,刷新ip信息(兼容动态ip服务器)
  let rule2 = new schedule.RecurrenceRule()
  rule2.hour = 2
  rule2.minute = 0
  rule2.second = 0
  schedule.scheduleJob(rule2, () => {
    console.log('Task: refresh ip info', new Date())
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
    serverSockets[socket.id] = setInterval(async () => {
      try {
        osData = await getOsData()
        socket && socket.emit('client_data', Object.assign(osData, { ipInfo }))
      } catch (error) {
        console.error('客户端错误：', error)
        socket && socket.emit('client_error', { error })
      }
    }, 1500)

    socket.on('disconnect', () => {
      if(serverSockets[socket.id]) clearInterval(serverSockets[socket.id])
      delete serverSockets[socket.id]
      socket.close && socket.close()
      socket = null
    })
  })
}
