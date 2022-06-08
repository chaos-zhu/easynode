const { Server: ServerIO } = require('socket.io')
const { io: ClientIO } = require('socket.io-client')
const { readHostList } = require('../utils')
const { clientPort } = require('../config')
const { verifyToken } = require('../utils')

let clientSockets = {}, clientsData = {}, timer = null

function getClientsInfo(socketId) {
  let hostList = readHostList()
  hostList
    .map(({ host }) => {
      let clientSocket = ClientIO(`http://${ host }:${ clientPort }`, {
        path: '/client/os-info',
        forceNew: true,
        reconnectionDelay: 3000,
        reconnectionAttempts: 1
      })
      clientSockets[socketId].push(clientSocket)
      return {
        host,
        clientSocket
      }
    })
    .map(({ host, clientSocket }) => {
      clientSocket
        .on('connect', () => {
          clientSocket.on('client_data', (osData) => {
            clientsData[host] = osData
          })
          clientSocket.on('client_error', (error) => {
            clientsData[host] = error
          })
        })
        .on('connect_error', () => {
          clientsData[host] = null
        })
        .on('disconnect', () => {
          clientsData[host] = null
        })
    })
}

module.exports = (httpServer) => {
  const serverIo = new ServerIO(httpServer, {
    path: '/clients',
    cors: {
    }
  })

  serverIo.on('connection', (socket) => {
    socket.on('init_clients_data', ({ token }) => {
      const { code } = verifyToken(token)
      if(code !== 1) return socket.emit('token_verify_fail', 'token无效')

      clientSockets[socket.id] = []

      getClientsInfo(socket.id)

      socket.emit('clients_data', clientsData)

      timer = setInterval(() => {
        socket.emit('clients_data', clientsData)
      }, 1500)

      socket.on('disconnect', () => {
        if(timer) clearInterval(timer)
        clientSockets[socket.id].forEach(socket => socket.close && socket.close())
        delete clientSockets[socket.id]
      })
    })
  })
}
