const { Server } = require('socket.io')
const { Client: Client } = require('ssh2')
const { readSSHRecord, verifyAuth, RSADecrypt, AESDecrypt } = require('../utils')

function createTerminal(socket, vps) {
  vps.shell({ term: 'xterm-color' }, (err, stream) => {
    if (err) return socket.emit('output', err.toString())
    stream
      .on('data', (data) => {
        socket.emit('output', data.toString())
      })
      .on('close', () => {
        console.log('关闭终端')
        vps.end()
      })
    socket.on('input', key => {
      if(vps._sock.writable === false) return console.log('终端连接已关闭')
      stream.write(key)
    })
    socket.emit('connect_terminal')

    socket.on('resize', ({ rows, cols }) => {
      stream.setWindow(rows, cols)
    })
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
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let clientIp = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    let vps = new Client()
    console.log('terminal websocket 已连接')

    socket.on('create', ({ host: ip, token }) => {
      const { code } = verifyAuth(token, clientIp)
      if(code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      // console.log('code:', code)
      const sshRecord = readSSHRecord()
      let loginInfo = sshRecord.find(item => item.host === ip)
      if(!sshRecord.some(item => item.host === ip)) return socket.emit('create_fail', `未找到【${ ip }】凭证`)
      let { type, host, port, username, randomKey } = loginInfo
      try {
        // 解密放到try里面，防止报错【公私钥必须配对, 否则需要重新添加服务器密钥】
        randomKey = AESDecrypt(randomKey) // 先对称解密key
        randomKey = RSADecrypt(randomKey) // 再非对称解密key
        loginInfo[type] = AESDecrypt(loginInfo[type], randomKey) // 对称解密ssh密钥
        console.log('准备连接服务器：', host)
        vps
          .on('ready', () => {
            console.log('已连接到服务器：', host)
            socket.emit('connect_success', `已连接到服务器：${ host }`)
            createTerminal(socket, vps)
          })
          .on('error', (err) => {
            console.log('连接失败:', err.level)
            socket.emit('connect_fail', err.message)
          })
          .connect({
            type: 'privateKey',
            host,
            port,
            username,
            [type]: loginInfo[type]
            // debug: (info) => {
            //   console.log(info)
            // }
          })
      } catch (err) {
        console.log('创建失败:', err.message)
        socket.emit('create_fail', err.message)
      }
    })

    socket.on('disconnect', (reason) => {
      console.log('终端连接断开:', reason)
      vps.end()
      vps.destroy()
      vps = null
    })
  })
}
