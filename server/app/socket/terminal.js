const path = require('path')
const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { verifyAuthSync } = require('../utils/verify-auth')
const { sendNoticeAsync } = require('../utils/notify')
const { isAllowedIp, ping } = require('../utils/tools')
const { AESDecryptAsync } = require('../utils/encrypt')
const { HostListDB, CredentialsDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const hostListDB = new HostListDB().getInstance()
const credentialsDB = new CredentialsDB().getInstance()

async function getConnectionOptions(hostId) {
  const hostInfo = await hostListDB.findOneAsync({ _id: hostId })
  if (!hostInfo) throw new Error(`Host with ID ${ hostId } not found`)
  let { authType, host, port, username, name } = hostInfo
  let authInfo = { host, port, username }
  try {
    if (authType === 'credential') {
      let credentialId = await AESDecryptAsync(hostInfo[authType])
      const sshRecord = await credentialsDB.findOneAsync({ _id: credentialId })
      authInfo.authType = sshRecord.authType
      authInfo[authInfo.authType] = await AESDecryptAsync(sshRecord[authInfo.authType])
    } else {
      authInfo[authType] = await AESDecryptAsync(hostInfo[authType])
    }
    return { authInfo, name }
  } catch (err) {
    throw new Error(`解密认证信息失败: ${ err.message }`)
  }
}

function createInteractiveShell(socket, targetSSHClient) {
  return new Promise((resolve) => {
    targetSSHClient.shell({ term: 'xterm-color' }, (err, stream) => {
      resolve(stream)
      if (err) return socket.emit('output', err.toString())
      stream
        .on('data', (data) => {
          socket.emit('output', data.toString())
        })
        .on('close', () => {
          consola.info('交互终端已关闭')
          targetSSHClient.end()
        })
      socket.emit('connect_shell_success') // 已连接终端，web端可以执行指令了
    })
  })
}

async function createTerminal(hostId, socket, targetSSHClient) {
  return new Promise(async (resolve) => {
    const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
    if (!targetHostInfo) return socket.emit('create_fail', `查找hostId【${ hostId }】凭证信息失败`)
    let { connectByJumpHosts = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
    let { authType, host, port, username, name, jumpHosts } = targetHostInfo
    try {
      let { authInfo: targetConnectionOptions } = await getConnectionOptions(hostId)
      let jumpHostResult = connectByJumpHosts && (await connectByJumpHosts(jumpHosts, targetConnectionOptions.host, targetConnectionOptions.port, socket))
      if (jumpHostResult) {
        targetConnectionOptions.sock = jumpHostResult.sock
      }

      socket.emit('terminal_print_info', `准备连接目标终端: ${ name } - ${ host }`)
      socket.emit('terminal_print_info', `连接信息: ssh ${ username }@${ host } -p ${ port }  ->  ${ authType }`)

      consola.info('准备连接目标终端：', host)
      consola.log('连接信息', { username, port, authType })
      let closeNoticeFlag = false // 避免重复发送通知
      targetSSHClient
        .on('ready', async () => {
          sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录成功`)
          socket.emit('terminal_print_info', `终端连接成功: ${ name } - ${ host }`)
          consola.success('终端连接成功：', host)
          socket.emit('connect_terminal_success', `终端连接成功：${ host }`)
          let stream = await createInteractiveShell(socket, targetSSHClient)
          resolve(stream)
        })
        .on('close', (err) => {
          if (closeNoticeFlag) return closeNoticeFlag = false
          const closeReason = err ? '发生错误导致连接断开' : '正常断开连接'
          consola.info(`终端连接断开(${ closeReason }): ${ host }`)
          socket.emit('connect_close', { reason: closeReason })
        })
        .on('error', (err) => {
          closeNoticeFlag = true
          sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录失败`)
          consola.error('连接终端失败:', host, err.message)
          socket.emit('connect_terminal_fail', err.message)
        })
        .on('keyboard-interactive', function (name, instructions, instructionsLang, prompts, finish) {
          finish([targetConnectionOptions[authType]])
        })
        .connect({
          tryKeyboard: true,
          ...targetConnectionOptions
          // debug: (info) => console.log(info)
        })
    } catch (err) {
      consola.error('创建终端失败: ', host, err.message)
      socket.emit('create_terminal_fail', err.message)
    }
  })
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/terminal',
    cors: {
      origin: '*'
    }
  })

  let connectionCount = 0

  serverIo.on('connection', (socket) => {
    connectionCount++
    consola.success(`terminal websocket 已连接 - 当前连接数: ${ connectionCount }`)
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    consola.success('terminal websocket 已连接')
    let targetSSHClient = null
    socket.on('create', async ({ hostId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      targetSSHClient = new SSHClient()
      let stream = null
      function listenerInput(key) {
        if (targetSSHClient._sock.writable === false) return consola.info('终端连接已关闭,禁止输入')
        stream && stream.write(key)
      }
      function resizeShell({ rows, cols }) {
        stream && stream.setWindow(rows, cols)
      }
      socket.on('input', listenerInput)
      socket.on('resize', resizeShell)
      stream = await createTerminal(hostId, socket, targetSSHClient)
    })

    socket.on('get_ping', async (ip) => {
      try {
        socket.emit('ping_data', await ping(ip, 2500))
      } catch (error) {
        socket.emit('ping_data', { success: false, msg: error.message })
      }
    })

    socket.on('disconnect', (reason) => {
      connectionCount--
      consola.info(`终端socket连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}

module.exports.getConnectionOptions = getConnectionOptions
