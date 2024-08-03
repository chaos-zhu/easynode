const { Server: ServerIO } = require('socket.io')
const { io: ClientIO, connect } = require('socket.io-client')
const { readHostList } = require('../utils')
const { clientPort } = require('../config')
const { verifyAuthSync } = require('../utils')

let clientsData = {}
async function getClientsInfo(clientSockets, clear = false) {
  clientSockets = []
  if (clear) clientsData = {}
  let hostList = await readHostList()
  hostList
    ?.map(({ host, name }) => {
      let clientSocket = ClientIO(`http://${ host }:${ clientPort }`, {
        path: '/client/os-info',
        forceNew: true,
        timeout: 5000,
        reconnectionDelay: 5000,
        reconnectionAttempts: 1000
      })
      // 将与客户端连接的socket实例保存起来，web端断开时关闭这些连接
      clientSockets.push(clientSocket)
      return {
        host,
        name,
        clientSocket
      }
    })
    .map(({ host, name, clientSocket }) => {
      clientsData[host] = { connect: false }
      clientSocket
        .on('connect', () => {
          consola.success('client connect success:', host, name)
          clientSocket.on('client_data', (osData) => {
            try {
              // clientsData[host] = { connect: true, osData: JSON.parse(osData) }
              clientsData[host] = { connect: true, ...osData }
            } catch (error) {
              console.warn('client_data, parse osData error: ', error.message)
            }
          })
          clientSocket.on('client_error', (error) => {
            clientsData[host] = { connect: true, error: `client_error: ${ error }` }
          })
        })
        .on('connect_error', (error) => { // 连接失败
          // consola.error('client connect fail:', host, name, error.message)
          try {
            clientsData[host] = { connect: false, error: `client_connect_error: ${ error }` }
          } catch (error) {
            console.warn('connect_error: ', error.message)
          }
        })
        .on('disconnect', (error) => { // 一方主动断开连接
          // consola.info('client connect disconnect:', host, name)
          try {
            clientsData[host] = { connect: false, error: `client_disconnect: ${ error }` }
          } catch (error) {
            console.warn('disconnect: ', error.message)
          }
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
    socket.on('init_clients_data', async ({ token }) => {
      const { code, msg } = await verifyAuthSync(token, clientIp)
      if (code !== 1) {
        socket.emit('token_verify_fail', msg || '鉴权失败')
        socket.disconnect()
        return
      }

      let clientSockets = []
      clientSockets.push(socket)

      getClientsInfo(clientSockets, true)
      socket.emit('clients_data', clientsData)

      socket.on('refresh_clients_data', async () => {
        consola.info('refresh clients-socket: ', clientSockets.length)
        getClientsInfo(clientSockets, false)
      })

      let timer = null
      timer = setInterval(() => {
        socket.emit('clients_data', clientsData)
      }, 1500)

      socket.on('disconnect', () => {
        if (timer) clearInterval(timer)
        clientSockets.forEach(socket => socket.close && socket.close())
        clientSockets = null
        clientsData = {}
        consola.info('clients-socket 连接断开: ', socket.id)
      })
    })
  })
}
