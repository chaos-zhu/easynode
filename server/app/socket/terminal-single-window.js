const path = require('path')
const { Server } = require('socket.io')
const decryptAndExecuteAsync = require('../utils/decrypt-file')

async function createServerIo(serverIo) {
  let { createSingleWindowServerIo = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (!createSingleWindowServerIo) {
    consola.info('单窗口模式功能未解锁')
    return
  }
  createSingleWindowServerIo(serverIo)
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/terminal-single-window',
    cors: {
      origin: '*'
    }
  })
  createServerIo(serverIo)
}
