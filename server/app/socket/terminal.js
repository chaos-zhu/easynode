const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { verifyAuthSync } = require('../utils/verify-auth')
const { AESDecryptSync } = require('../utils/encrypt')
const { readSSHRecord, readHostList } = require('../utils/storage')
const { asyncSendNotice } = require('../utils/notify')

function createInteractiveShell(socket, sshClient) {
  return new Promise((resolve) => {
    sshClient.shell({ term: 'xterm-color' }, (err, stream) => {
      resolve(stream)
      if (err) return socket.emit('output', err.toString())
      // 终端输出
      stream
        .on('data', (data) => {
          socket.emit('output', data.toString())
        })
        .on('close', () => {
          consola.info('交互终端已关闭')
          sshClient.end()
        })
      socket.emit('connect_shell_success') // 已连接终端，web端可以执行指令了
    })
  })
}

function execShell(sshClient, command = '', callback) {
  if (!command) return
  let result = ''
  sshClient.exec(`source ~/.bashrc && ${ command }`, (err, stream) => {
    if (err) return callback(err.toString())
    stream
      .on('data', (data) => {
        result += data.toString()
      })
      .stderr
      .on('data', (data) => {
        result += data.toString()
      })
      .on('close', () => {
        consola.info('一次性指令执行完成:', command)
        callback(result)
      })
      .on('error', (error) => {
        console.log('Error:', error.toString())
      })
  })
}

async function createTerminal(ip, socket, sshClient) {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise(async (resolve) => {
    const hostList = await readHostList()
    const targetHostInfo = hostList.find(item => item.host === ip) || {}
    let { authType, host, port, username, name } = targetHostInfo
    if (!host) return socket.emit('create_fail', `查找【${ ip }】凭证信息失败`)
    let authInfo = { host, port, username }
    // 统一使用commonKey解密
    try {
    // 解密放到try里面，防止报错【commonKey必须配对, 否则需要重新添加服务器密钥】
      if (authType === 'credential') {
        let credentialId = await AESDecryptSync(targetHostInfo[authType])
        const sshRecordList = await readSSHRecord()
        const sshRecord = sshRecordList.find(item => item._id === credentialId)
        authInfo.authType = sshRecord.authType
        authInfo[authInfo.authType] = await AESDecryptSync(sshRecord[authInfo.authType])
      } else {
        authInfo[authType] = await AESDecryptSync(targetHostInfo[authType])
      }
      consola.info('准备连接终端：', host)
      // targetHostInfo[targetHostInfo.authType] = await AESDecryptSync(targetHostInfo[targetHostInfo.authType])
      consola.log('连接信息', { username, port, authType })
      sshClient
        .on('ready', async() => {
          asyncSendNotice('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录成功`)
          consola.success('终端连接成功：', host)
          socket.emit('connect_terminal_success', `终端连接成功：${ host }`)
          let stream = await createInteractiveShell(socket, sshClient)
          resolve(stream)
        // execShell(sshClient, 'history', (data) => {
        //   data = data.split('\n').filter(item => item)
        //   console.log(data)
        //   socket.emit('terminal_command_history', data)
        // })
        })
        .on('close', () => {
          consola.info('终端连接断开close: ', host)
          socket.emit('connect_close')
        })
        .on('error', (err) => {
          consola.log(err)
          asyncSendNotice('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录失败`)
          consola.error('连接终端失败:', host, err.message)
          socket.emit('connect_fail', err.message)
        })
        .connect({
          ...authInfo
        // debug: (info) => console.log(info)
        })
    } catch (err) {
      consola.error('创建终端失败: ', host, err.message)
      socket.emit('create_fail', err.message)
    }
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
    consola.success('terminal websocket 已连接')
    let sshClient = null
    socket.on('create', async ({ host: ip, token }) => {
      const { code } = await verifyAuthSync(token, clientIp)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      sshClient = new SSHClient()

      // 尝试手动断开调试，再次连接后终端输出内容为4份相同的输出，导致异常
      // setTimeout(() => {
      //   sshClient.end()
      // }, 3000)
      let stream = null

      function listenerInput(key) {
        if (sshClient._sock.writable === false) return consola.info('终端连接已关闭,禁止输入')
        stream && stream.write(key)
      }
      function resizeShell({ rows, cols }) {
        // consola.info('更改tty终端行&列: ', { rows, cols })
        stream && stream.setWindow(rows, cols)
      }
      socket.on('input', listenerInput)
      socket.on('resize', resizeShell)
      // 重连
      socket.on('reconnect_terminal', async () => {
        consola.info('重连终端: ', ip)
        socket.off('input', listenerInput) // 取消监听,重新注册监听,操作新的stream
        socket.off('resize', resizeShell)
        sshClient?.end()
        sshClient?.destroy()
        sshClient = null
        stream = null
        setTimeout(async () => {
          // 初始化新的SSH客户端对象
          sshClient = new SSHClient()
          stream = await createTerminal(ip, socket, sshClient)
          socket.emit('reconnect_terminal_success')
          socket.on('input', listenerInput)
          socket.on('resize', resizeShell)
        }, 3000)
      })
      stream = await createTerminal(ip, socket, sshClient)
    })

    socket.on('disconnect', (reason) => {
      consola.info('终端socket连接断开:', reason)
    })
  })
}
