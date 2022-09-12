const { Server: ServerIO } = require('socket.io')
const { io: ClientIO } = require('socket.io-client')
const { readHostList } = require('../utils')
const { clientPort } = require('../config')
const { verifyAuth } = require('../utils')

let clientSockets = {}, clientsData = {}

function getClientsInfo(socketId) {
  let hostList = readHostList()
  hostList
    .map(({ host, name }) => {
      let clientSocket = ClientIO(`http://${ host }:${ clientPort }`, {
        path: '/client/os-info',
        forceNew: true,
        timeout: 5000,
        reconnectionDelay: 3000,
        reconnectionAttempts: 100
      })
      // 将与客户端连接的socket实例保存起来，web端断开时关闭这些连接
      clientSockets[socketId].push(clientSocket)
      return {
        host,
        name,
        clientSocket
      }
    })
    .map(({ host, name, clientSocket }) => {
      clientSocket
        .on('connect', () => {
          consola.success('client connect success:', host, name)
          clientSocket.on('client_data', (osData) => {
            clientsData[host] = osData
          })
          clientSocket.on('client_error', (error) => {
            clientsData[host] = error
          })
        })
        .on('connect_error', (error) => {
          consola.error('client connect fail:', host, name, error.message)
          clientsData[host] = null
        })
        .on('disconnect', () => {
          consola.info('client connect disconnect:', host, name)
          clientsData[host] = null
        })
    })
}

module.exports = (httpServer) => {
  const serverIo = new ServerIO(httpServer, {
    path: '/clients',
    cors: {
      origin: '*' // 需配置跨域
    }
  })

  serverIo.on('connection', (socket) => {
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let clientIp = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    socket.on('init_clients_data', ({ token }) => {
      // 校验登录态
      const { code, msg } = verifyAuth(token, clientIp)
      if(code !== 1) {
        socket.emit('token_verify_fail', msg || '鉴权失败')
        socket.disconnect()
        return
      }

      // 收集web端连接的id
      clientSockets[socket.id] = []
      consola.info('client连接socketId: ', socket.id, 'clients-socket已连接数: ', Object.keys(clientSockets).length)

      // 获取客户端数据
      getClientsInfo(socket.id)

      // 立即推送一次
      socket.emit('clients_data', clientsData)

      // 向web端推送数据
      let timer = null
      timer = setInterval(() => {
        socket.emit('clients_data', clientsData)
      }, 1000)

      // 关闭连接
      socket.on('disconnect', () => {
        // 防止内存泄漏
        if(timer) clearInterval(timer)
        // 当web端与服务端断开连接时, 服务端与每个客户端的socket也应该断开连接
        clientSockets[socket.id].forEach(socket => socket.close && socket.close())
        delete clientSockets[socket.id]
        consola.info('断开socketId: ', socket.id, 'clients-socket剩余连接数: ', Object.keys(clientSockets).length)
      })
    })
  })
}
