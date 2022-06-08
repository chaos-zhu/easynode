const { Server } = require('socket.io')
const { Client: Client } = require('ssh2')
const { readSSHRecord, verifyToken } = require('../utils')

function createTerminal(socket, vps) {
  vps.shell({ term: 'xterm-color', cols: 100, rows: 30 }, (err, stream) => {
    if (err) return socket.emit('output', err.toString())
    stream
      .on('data', (data) => {
        socket.emit('output', data.toString())
      })
      .on('close', () => {
        vps.end()
      })
    socket.on('input', key => {
      if(vps._sock.writable === false) return console.log('终端连接已关闭')
      stream.write(key)
    })
    socket.emit('connect_terminal')

  })
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/terminal',
    cors: {
      origin: '*'
    }
  })
  serverIo.on('connection', (socket) => {
    let vps = new Client()

    socket.on('create', ({ host: ip, token }) => {

      const { code } = verifyToken(token)
      if(code !== 1) return socket.emit('token_verify_fail')

      const sshRecord = readSSHRecord()
      let loginInfo = sshRecord.find(item => item.host === ip)
      if(!sshRecord.some(item => item.host === ip)) return socket.emit('create_fail', `未找到【${ ip }】凭证`)
      const { type, host, port, username } = loginInfo
      try {
        vps
          .on('ready', () => {
            socket.emit('connect_success', `已连接到服务器：${ host }`)
            createTerminal(socket, vps)
          })
          .on('error', (err) => {
            socket.emit('connect_fail', err.message)
          })
          .connect({
            type: 'privateKey',
            host,
            port,
            username,
            [type]: loginInfo[type]

          })
      } catch (err) {
        socket.emit('create_fail', err.message)
      }
    })

    socket.on('disconnect', () => {
      vps.end()
      vps.destroy()
      vps = null
    })
  })
}
