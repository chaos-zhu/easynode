const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { readSSHRecord, verifyAuth, RSADecrypt, AESDecrypt } = require('../utils')

function createTerminal(socket, sshClient) {
  sshClient.shell({ term: 'xterm-color' }, (err, stream) => {
    if (err) return socket.emit('output', err.toString())
    // 终端输出
    stream
      .on('data', (data) => {
        socket.emit('output', data.toString())
      })
      .on('close', () => {
        consola.info('关闭终端')
        sshClient.end()
      })
    // web端输入
    socket.on('input', key => {
      if(sshClient._sock.writable === false) return consola.info('终端连接已关闭')
      stream.write(key)
    })
    socket.emit('connect_terminal') // 已连接终端，web端可以执行指令了

    // 监听按键重置终端大小
    socket.on('resize', ({ rows, cols }) => {
      consola.info('更改tty终端行&列: ', { rows, cols })
      stream.setWindow(rows, cols)
    })
  })
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/terminal',
    cors: {
      origin: '*' // 'http://localhost:8080'
    }
  })
  serverIo.on('connection', (socket) => {
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let clientIp = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    let sshClient = new SSHClient()
    consola.success('terminal websocket 已连接')

    socket.on('create', ({ host: ip, token }) => {
      const { code } = verifyAuth(token, clientIp)
      if(code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      const sshRecord = readSSHRecord()
      let loginInfo = sshRecord.find(item => item.host === ip)
      if(!sshRecord.some(item => item.host === ip)) return socket.emit('create_fail', `未找到【${ ip }】凭证`)
      let { type, host, port, username, randomKey } = loginInfo
      try {
        // 解密放到try里面，防止报错【公私钥必须配对, 否则需要重新添加服务器密钥】
        randomKey = AESDecrypt(randomKey) // 先对称解密key
        randomKey = RSADecrypt(randomKey) // 再非对称解密key
        loginInfo[type] = AESDecrypt(loginInfo[type], randomKey) // 对称解密ssh密钥
        consola.info('准备连接终端：', host)
        const authInfo = { host, port, username, [type]: loginInfo[type] }
        sshClient
          .on('ready', () => {
            consola.success('已连接到终端：', host)
            socket.emit('connect_success', `已连接到终端：${ host }`)
            createTerminal(socket, sshClient)
          })
          .on('error', (err) => {
            consola.error('连接终端失败:', err.level)
            socket.emit('connect_fail', err.message)
          })
          .connect(authInfo)
      } catch (err) {
        consola.error('创建终端失败:', err.message)
        socket.emit('create_fail', err.message)
      }
    })

    socket.on('disconnect', (reason) => {
      consola.info('终端连接断开:', reason)
      sshClient.end()
      sshClient.destroy()
      sshClient = null
    })
  })
}
