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
  return new Promise((resolve, reject) => {
    // 检查SSH客户端连接状态
    if (!targetSSHClient || !targetSSHClient._sock || !targetSSHClient._sock.writable) {
      const errorMsg = 'SSH客户端连接已断开，无法创建交互式终端'
      consola.error(errorMsg)
      socket.emit('terminal_connect_fail', errorMsg)
      return reject(new Error(errorMsg))
    }

    try {
      targetSSHClient.shell({ term: 'xterm-color' }, (err, stream) => {
        if (err) {
          consola.error('创建交互式终端失败:', err.message)
          socket.emit('terminal_connect_fail', err.message)
          return reject(err)
        }

        resolve(stream)

        stream
          .on('data', (data) => {
            socket.emit('output', data.toString())
          })
          .on('close', () => {
            consola.info('交互终端已关闭')
            targetSSHClient.end()
          })
          .on('error', (streamErr) => {
            consola.error('终端流错误:', streamErr.message)
            socket.emit('terminal_connect_fail', streamErr.message)
          })

        socket.emit('terminal_connect_shell_success') // 已连接终端，web端可以执行指令了
      })
    } catch (shellError) {
      consola.error('调用shell方法失败:', shellError.message)
      socket.emit('terminal_connect_fail', shellError.message)
      reject(shellError)
    }
  })
}

async function createTerminal(hostId, socket, targetSSHClient, isInteractiveShell = true) {
  consola.info(`准备创建${ isInteractiveShell ? '交互式' : '非交互式' }终端：${ hostId }`)
  return new Promise(async (resolve) => {
    const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
    if (!targetHostInfo) return socket.emit('create_fail', `查找hostId【${ hostId }】凭证信息失败`)
    let { connectByJumpHosts = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
    let { authType, host, port, username, name, jumpHosts } = targetHostInfo
    try {
      let { authInfo: targetConnectionOptions } = await getConnectionOptions(hostId)
      let jumpHostResult = connectByJumpHosts && (await connectByJumpHosts(jumpHosts, targetConnectionOptions.host, targetConnectionOptions.port, socket))
      let jumpSshClients = []
      if (jumpHostResult) {
        targetConnectionOptions.sock = jumpHostResult.sock
        jumpSshClients = jumpHostResult.sshClients
      }

      socket.emit('terminal_print_info', `准备连接目标终端: ${ name } - ${ host }`)
      socket.emit('terminal_print_info', `连接信息: ssh ${ username }@${ host } -p ${ port }  ->  ${ authType }`)
      consola.info('准备连接目标终端：', host)
      consola.log('连接信息', { username, port, authType })

      let closeNoticeFlag = false // 避免重复发送通知
      targetSSHClient
        .on('ready', async () => {
          consola.success('终端连接成功：', host)
          if (isInteractiveShell) {
            sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录成功`)
            socket.emit('terminal_print_info', `终端连接成功: ${ name } - ${ host }`)
            socket.emit('terminal_connect_success', `终端连接成功：${ host }`)

            try {
              let stream = await createInteractiveShell(socket, targetSSHClient)
              resolve({ stream, jumpSshClients })
            } catch (shellError) {
              consola.error('创建交互式终端失败:', host, shellError.message)
              // 连接已经成功但创建shell失败，需要清理连接
              targetSSHClient.end()
              jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
            }
          } else {
            resolve({ jumpSshClients })
          }
        })
        .on('close', (err) => {
          if (closeNoticeFlag) return closeNoticeFlag = false
          const closeReason = err ? '发生错误导致连接断开' : '正常断开连接'
          consola.info(`终端连接断开(${ closeReason }): ${ host }`)
          socket.emit('terminal_connect_close', { reason: closeReason })
        })
        .on('error', (err) => {
          closeNoticeFlag = true
          sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录失败`)
          consola.error('连接终端失败:', host, err.message)
          socket.emit('terminal_connect_fail', err.message)
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
      socket.emit('terminal_create_fail', err.message)
    }
  })
}

function createServerIo(serverIo) {
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
    let jumpSshClients = []
    socket.on('ws_terminal', async ({ hostId, token }) => {
      try {
        const { code } = await verifyAuthSync(token, requestIP)
        if (code !== 1) {
          socket.emit('token_verify_fail')
          socket.disconnect()
          return
        }

        targetSSHClient = new SSHClient()
        let result = await createTerminal(hostId, socket, targetSSHClient, true)

        // 如果创建终端失败，result可能为undefined
        if (!result) {
          consola.error('创建终端失败，未返回结果')
          return
        }

        let { stream = null, jumpSshClients: jumpSshClientsFromCreate } = result
        jumpSshClients = jumpSshClientsFromCreate || []

        const listenerInput = (key) => {
          if (!targetSSHClient || !targetSSHClient._sock || !targetSSHClient._sock.writable) {
            consola.info('终端连接已关闭,禁止输入')
            return
          }
          stream && stream.write(key)
        }

        const resizeShell = ({ rows, cols }) => {
          stream && stream.setWindow(rows, cols)
        }

        socket.on('input', listenerInput)
        socket.on('resize', resizeShell)
      } catch (error) {
        consola.error('ws_terminal事件处理失败:', error.message)
        socket.emit('terminal_connect_fail', `连接失败: ${ error.message }`)
      }
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
      targetSSHClient && targetSSHClient.end()
      jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
      targetSSHClient = null
      jumpSshClients = null
      consola.info(`终端socket连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
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
  createServerIo(serverIo)
}

module.exports.getConnectionOptions = getConnectionOptions
module.exports.createTerminal = createTerminal
module.exports.createServerIo = createServerIo
