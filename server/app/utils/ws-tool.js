import { Server } from 'socket.io'
import { verifyWsAuthSync } from './verify-auth.js'

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

export {
  createSecureWs
}
