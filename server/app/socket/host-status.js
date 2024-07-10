const { Server: ServerIO } = require('socket.io')
const { io: ClientIO } = require('socket.io-client')
const { clientPort } = require('../config')
const { verifyAuthSync } = require('../utils')

let hostSockets = {}

function getHostInfo(serverSocket, host) {
  let hostSocket = ClientIO(`http://${ host }:${ clientPort }`, {
    path: '/client/os-info',
    forceNew: false,
    timeout: 5000,
    reconnectionDelay: 3000,
    reconnectionAttempts: 100
  })
  // 将与客户端连接的socket实例保存起来，web端断开时关闭与客户端的连接
  hostSockets[serverSocket.id] = hostSocket

  hostSocket
    .on('connect', () => {
      consola.success('host-status-socket连接成功:', host)
      hostSocket.on('client_data', (data) => {
        serverSocket.emit('host_data', data)
      })
      hostSocket.on('client_error', () => {
        serverSocket.emit('host_data', null)
      })
    })
    .on('connect_error', (error) => {
      consola.error('host-status-socket连接[失败]:', host, error.message)
      serverSocket.emit('host_data', null)
    })
    .on('disconnect', () => {
      consola.info('host-status-socket连接[断开]:', host)
      serverSocket.emit('host_data', null)
    })
}

module.exports = (httpServer) => {
  const serverIo = new ServerIO(httpServer, {
    path: '/host-status',
    cors: {
      origin: '*' // 需配置跨域
    }
  })

  serverIo.on('connection', (serverSocket) => {
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let clientIp = serverSocket.handshake.headers['x-forwarded-for'] || serverSocket.handshake.address
    serverSocket.on('init_host_data', async ({ token, host }) => {
      // 校验登录态
      const { code, msg } = await verifyAuthSync(token, clientIp)
      if(code !== 1) {
        serverSocket.emit('token_verify_fail', msg || '鉴权失败')
        serverSocket.disconnect()
        return
      }

      // 获取客户端数据
      getHostInfo(serverSocket, host)

      consola.info('host-status-socket连接socketId: ', serverSocket.id, 'host-status-socket已连接数: ', Object.keys(hostSockets).length)

      // 关闭连接
      serverSocket.on('disconnect', () => {
        // 当web端与服务端断开连接时, 服务端与每个客户端的socket也应该断开连接
        let socket = hostSockets[serverSocket.id]
        socket.close && socket.close()
        delete hostSockets[serverSocket.id]
        consola.info('host-status-socket剩余连接数: ', Object.keys(hostSockets).length)
      })
    })
  })
}
