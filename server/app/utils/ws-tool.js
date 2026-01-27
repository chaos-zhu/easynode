const { Server } = require('socket.io')
const { verifyWsAuthSync } = require('./verify-auth')

const createSecureWs = (httpServer, path, otherConfig = {}) => {
  const serverIo = new Server(httpServer, {
    path,
    cors: {
      origin: true,
      credentials: true
    },
    ...otherConfig
  })
  // 鉴权
  serverIo.use(verifyWsAuthSync)

  return serverIo
}

module.exports = {
  createSecureWs
}