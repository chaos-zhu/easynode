const path = require('path')
const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { verifyAuthSync } = require('../utils/verify-auth')
const { sendNoticeAsync } = require('../utils/notify')
const { isAllowedIp, ping } = require('../utils/tools')
const { AESDecryptAsync } = require('../utils/encrypt')
const { HostListDB, CredentialsDB, ProxyDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const hostListDB = new HostListDB().getInstance()
const credentialsDB = new CredentialsDB().getInstance()
const proxyDB = new ProxyDB().getInstance()

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
      if (authInfo.authType === 'privateKey' && sshRecord.openSSHKeyPassword) {
        authInfo.passphrase = sshRecord.openSSHKeyPassword
      }
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
      logger.error(errorMsg)
      socket.emit('terminal_connect_fail', errorMsg)
      return reject(new Error(errorMsg))
    }

    try {
      targetSSHClient.shell({ term: 'xterm-color' }, (err, stream) => {
        if (err) {
          logger.error('创建交互式终端失败:', err.message)
          socket.emit('terminal_connect_fail', err.message)
          return reject(err)
        }

        resolve(stream)

        stream
          .on('data', (data) => {
            socket.emit('output', data.toString())
          })
          .on('close', () => {
            logger.info('交互终端已关闭')
            targetSSHClient.end()
          })
          .on('error', (streamErr) => {
            logger.error('终端流错误:', streamErr.message)
            socket.emit('terminal_connect_fail', streamErr.message)
          })

        socket.emit('terminal_connect_shell_success') // 已连接终端，web端可以执行指令了
      })
    } catch (shellError) {
      logger.error('调用shell方法失败:', shellError.message)
      socket.emit('terminal_connect_fail', shellError.message)
      reject(shellError)
    }
  })
}

// 获取代理配置信息
async function getProxyConfig(proxyId) {
  if (!proxyId) return null
  try {
    const proxyInfo = await proxyDB.findOneAsync({ _id: proxyId })
    if (!proxyInfo) {
      throw new Error(`代理配置 ID ${ proxyId } 未找到`)
    }

    return {
      id: proxyInfo._id,
      name: proxyInfo.name,
      type: proxyInfo.type, // 'socks5' 或 'http'
      host: proxyInfo.host,
      port: proxyInfo.port,
      username: proxyInfo.username || '',
      password: proxyInfo.password || ''
    }
  } catch (error) {
    logger.error('获取代理配置失败:', error.message)
    throw error
  }
}

// 通用的代理和跳板机连接处理函数
async function handleProxyAndJumpHostConnection(options) {
  const {
    hostInfo,
    targetConnectionOptions,
    socket,
    logPrefix = ''
  } = options

  const { proxyType, proxyServer, jumpHosts, host } = hostInfo
  let jumpSshClients = []

  try {
    // 代理连接
    if (proxyType === 'proxyServer' && proxyServer) {
      const proxyConfig = await getProxyConfig(proxyServer)
      if (proxyConfig) {
        const logMsg = `${ logPrefix }使用代理服务器: ${ proxyConfig.name } (${ proxyConfig.type.toUpperCase() }) - ${ proxyConfig.host }:${ proxyConfig.port }`
        logger.info(logMsg)

        // 向前端发送代理信息（如果socket存在且有对应方法）
        if (socket && socket.emit) {
          if (typeof socket.emit === 'function') {
            try {
              socket.emit('terminal_print_info', `使用代理服务器: ${ proxyConfig.name } (${ proxyConfig.type.toUpperCase() }) - ${ proxyConfig.host }:${ proxyConfig.port }`)
            } catch (emitError) {
              // 忽略emit错误，因为不同socket可能有不同的事件
            }
          }
        }

        let proxySocket
        if (proxyConfig.type === 'socks5') {
          const { createSocks5Connection = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
          if (!createSocks5Connection) throw new Error('Plus功能解锁失败: createSocks5Connection')
          proxySocket = await createSocks5Connection(proxyConfig, targetConnectionOptions.host, targetConnectionOptions.port)
        } else if (proxyConfig.type === 'http') {
          const { createHttpConnection = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
          if (!createHttpConnection) throw new Error('Plus功能解锁失败: createHttpConnection')
          proxySocket = await createHttpConnection(proxyConfig, targetConnectionOptions.host, targetConnectionOptions.port)
        } else {
          throw new Error(`不支持的代理类型: ${ proxyConfig.type }`)
        }

        targetConnectionOptions.sock = proxySocket
        logger.info(`${ logPrefix }代理连接建立成功: ${ host }`)

        // 向前端发送成功信息
        if (socket && socket.emit && typeof socket.emit === 'function') {
          try {
            socket.emit('terminal_print_info', '代理连接建立成功，准备通过代理连接目标服务器')
          } catch (emitError) {
            // 忽略emit错误
          }
        }
      }
    }
    // 跳板机连接
    else if (proxyType === 'jumpHosts' && Array.isArray(jumpHosts) && jumpHosts.length > 0) {
      const { connectByJumpHosts = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
      if (!connectByJumpHosts) throw new Error('Plus功能解锁失败: connectByJumpHosts')
      const jumpHostResult = await connectByJumpHosts(jumpHosts, targetConnectionOptions.host, targetConnectionOptions.port, socket)
      if (jumpHostResult) {
        targetConnectionOptions.sock = jumpHostResult.sock
        jumpSshClients = jumpHostResult.sshClients
        logger.info(`${ logPrefix }跳板机连接成功`)
      }
    }

    return {
      targetConnectionOptions,
      jumpSshClients
    }
  } catch (error) {
    logger.error(`${ logPrefix }连接失败:`, error.message)
    throw error
  }
}

async function createTerminal(hostId, socket, targetSSHClient, isInteractiveShell = true) {
  logger.info(`准备创建${ isInteractiveShell ? '交互式' : '非交互式' }终端：${ hostId }`)
  return new Promise(async (resolve) => {
    const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
    if (!targetHostInfo) return socket.emit('create_fail', `查找hostId【${ hostId }】凭证信息失败`)
    let { authType, host, port, username, name } = targetHostInfo
    try {
      let { authInfo: targetConnectionOptions } = await getConnectionOptions(hostId)

      // 使用通用的代理和跳板机连接处理函数
      let jumpSshClients = []
      try {
        const result = await handleProxyAndJumpHostConnection({
          hostInfo: targetHostInfo,
          targetConnectionOptions,
          socket,
          logPrefix: 'Terminal '
        })
        jumpSshClients = result.jumpSshClients
      } catch (proxyError) {
        socket.emit('terminal_connect_fail', `代理连接失败: ${ proxyError.message }`)
        return
      }

      socket.emit('terminal_print_info', `准备连接目标终端: ${ name } - ${ host }`)
      socket.emit('terminal_print_info', `连接信息: ssh ${ username }@${ host } -p ${ port }  ->  ${ authType }`)
      logger.info('准备连接目标终端：', host)
      logger.info('连接信息', { username, port, authType })

      let closeNoticeFlag = false // 避免重复发送通知
      targetSSHClient
        .on('ready', async () => {
          logger.info('终端连接成功：', host)
          if (isInteractiveShell) {
            sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录成功`)
            socket.emit('terminal_print_info', `终端连接成功: ${ name } - ${ host }`)
            socket.emit('terminal_connect_success', `终端连接成功：${ host }`)

            try {
              let stream = await createInteractiveShell(socket, targetSSHClient)
              resolve({ stream, jumpSshClients })
            } catch (shellError) {
              logger.error('创建交互式终端失败:', host, shellError.message)
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
          logger.info(`终端连接断开(${ closeReason }): ${ host }`)
          socket.emit('terminal_connect_close', { reason: closeReason })
        })
        .on('error', (err) => {
          closeNoticeFlag = true
          sendNoticeAsync('host_login', '终端登录', `别名: ${ name } \n IP：${ host } \n 端口：${ port } \n 状态: 登录失败`)
          logger.error('连接终端失败:', host, err.message)
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
      logger.error('创建终端失败: ', host, err.message)
      socket.emit('terminal_create_fail', err.message)
    }
  })
}

function createServerIo(serverIo) {
  let connectionCount = 0

  serverIo.on('connection', async (socket) => {
    // IP白名单检查
    const requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    // 登录态校验
    const { token, uid } = socket.handshake.query
    const { success } = await verifyAuthSync(token, uid)
    if (!success) {
      socket.emit('user_verify_fail')
      socket.disconnect()
      return
    }
    connectionCount++
    logger.info(`terminal websocket 已连接 - 当前连接数: ${ connectionCount }`)
    let targetSSHClient = null
    let jumpSshClients = []
    socket.on('ws_terminal', async ({ hostId }) => {
      try {
        targetSSHClient = new SSHClient()
        let result = await createTerminal(hostId, socket, targetSSHClient, true)

        // 如果创建终端失败，result可能为undefined
        if (!result) {
          logger.error('创建终端失败，未返回结果')
          return
        }

        let { stream = null, jumpSshClients: jumpSshClientsFromCreate } = result
        jumpSshClients = jumpSshClientsFromCreate || []

        const listenerInput = (key) => {
          if (!targetSSHClient || !targetSSHClient._sock || !targetSSHClient._sock.writable) {
            logger.info('终端连接已关闭,禁止输入')
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
        logger.error('ws_terminal事件处理失败:', error.message)
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
      logger.info(`终端socket连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
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
module.exports.getProxyConfig = getProxyConfig
module.exports.handleProxyAndJumpHostConnection = handleProxyAndJumpHostConnection
