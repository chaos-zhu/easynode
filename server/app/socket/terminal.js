const path = require('path')
const { Client: SSHClient } = require('ssh2')
const { sendNoticeAsync } = require('../utils/notify')
const { ping } = require('../utils/tools')
const { AESDecryptAsync } = require('../utils/encrypt')
const { KeyDB, HostListDB, CredentialsDB, ProxyDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { sessionManager, SessionStatus } = require('./session-manager')
const { createSecureWs } = require('../utils/ws-tool')

const hostListDB = new HostListDB().getInstance()
const credentialsDB = new CredentialsDB().getInstance()
const proxyDB = new ProxyDB().getInstance()
const keyDB = new KeyDB().getInstance()

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
              // 返回连接配置，用于会话重连
              resolve({ stream, jumpSshClients, connectionOptions: targetConnectionOptions })
            } catch (shellError) {
              logger.error('创建交互式终端失败:', host, shellError.message)
              // 连接已经成功但创建shell失败，需要清理连接
              targetSSHClient.end()
              jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
            }
          } else {
            resolve({ jumpSshClients, connectionOptions: targetConnectionOptions })
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

/**
 * 恢复挂起的会话
 * @param {Object} socket - Socket.IO socket实例
 * @param {Object} session - 要恢复的会话
 */
function resumeSession(socket, session) {
  const { sessionId, stream, sshClient } = session

  // 恢复会话状态
  const resumedSession = sessionManager.resumeSession(sessionId)
  if (!resumedSession) {
    socket.emit('terminal_connect_fail', '恢复会话失败：SSH连接已断开')
    return false
  }

  // 绑定socket
  sessionManager.bindSocket(socket.id, sessionId)

  // 获取并发送缓存的输出
  const bufferedOutput = session.flushBuffer()

  // 重新绑定stream的data事件，发送到前端
  stream.removeAllListeners('data')
  stream.on('data', (data) => {
    socket.emit('output', data.toString())
  })

  // 设置输入监听
  const listenerInput = (key) => {
    if (!sshClient?._sock?.writable) {
      logger.info('终端连接已关闭,禁止输入')
      return
    }
    stream?.write(key)
  }

  const resizeShell = ({ rows, cols }) => {
    stream?.setWindow(rows, cols)
  }

  socket.on('input', listenerInput)
  socket.on('resize', resizeShell)

  // 通知前端恢复成功
  socket.emit('terminal_resumed', {
    sessionId,
    hostId: session.hostId,
    bufferedOutput
  })

  socket.emit('session_created', { sessionId })
  socket.emit('terminal_connect_success', '终端恢复连接成功')
  socket.emit('terminal_connect_shell_success')

  logger.info(`终端已恢复: ${ sessionId }`)
  return true
}

function createServerIo(serverIo) {
  let connectionCount = 0

  serverIo.on('connection', async (socket) => {
    connectionCount++
    logger.info(`terminal websocket 已连接 - 当前连接数: ${ connectionCount }`)

    const { _id: userId } = await keyDB.findOneAsync({})
    // 处理终端连接请求
    socket.on('ws_terminal', async ({ hostId, forceNew = false, resumeSessionId = null }) => {
      try {
        // 如果指定了resumeSessionId，尝试恢复该会话
        if (resumeSessionId) {
          const session = sessionManager.getSession(resumeSessionId)
          if (session && session.userId === userId && session.hostId === hostId) {
            logger.info(`尝试恢复指定会话 ${ resumeSessionId }`)
            const resumed = resumeSession(socket, session)
            if (resumed) {
              return // 恢复成功，直接返回
            }
            // 恢复失败，继续创建新连接
            logger.info('恢复指定会话失败，创建新连接')
          } else {
            logger.warn(`会话 ${ resumeSessionId } 不存在或无权访问`)
            socket.emit('terminal_connect_fail', '会话不存在或已过期')
            return
          }
        }

        // 检查是否有该主机的挂起会话（仅在非forceNew时自动恢复）
        if (!forceNew && !resumeSessionId) {
          const suspendedSession = sessionManager.findSuspendedSession(userId, hostId)
          if (suspendedSession) {
            logger.info(`发现挂起会话 ${ suspendedSession.sessionId }，尝试自动恢复`)
            const resumed = resumeSession(socket, suspendedSession)
            if (resumed) {
              return // 恢复成功，直接返回
            }
            // 恢复失败，继续创建新连接
            logger.info('自动恢复会话失败，创建新连接')
          }
        }

        // 创建新连接
        const targetSSHClient = new SSHClient()
        let result = await createTerminal(hostId, socket, targetSSHClient, true)

        // 如果创建终端失败，result可能为undefined
        if (!result) {
          logger.error('创建终端失败，未返回结果')
          return
        }

        let { stream = null, jumpSshClients = [], connectionOptions = null } = result

        // 创建会话并注册
        const session = sessionManager.createSession({
          hostId,
          userId,
          sshClient: targetSSHClient,
          stream,
          jumpSshClients,
          connectionOptions // 保存连接配置，用于重连
        })

        // 绑定socket与会话
        sessionManager.bindSocket(socket.id, session.sessionId)

        // 通知前端会话ID
        socket.emit('session_created', { sessionId: session.sessionId })

        // 设置输入监听
        const listenerInput = (key) => {
          if (!targetSSHClient?._sock?.writable) {
            logger.info('终端连接已关闭,禁止输入')
            return
          }
          stream?.write(key)
        }

        const resizeShell = ({ rows, cols }) => {
          stream?.setWindow(rows, cols)
        }

        socket.on('input', listenerInput)
        socket.on('resize', resizeShell)

      } catch (error) {
        logger.error('ws_terminal事件处理失败:', error.message)
        socket.emit('terminal_connect_fail', `连接失败: ${ error.message }`)
      }
    })

    // 挂起终端
    socket.on('suspend_terminal', ({ sessionId }) => {
      const session = sessionManager.getSession(sessionId)
      if (!session) {
        socket.emit('suspend_fail', '会话不存在')
        return
      }

      if (session.userId !== userId) {
        socket.emit('suspend_fail', '无权操作此会话')
        return
      }

      // 标记为挂起状态（内部会检查挂起数量限制）
      const suspendResult = sessionManager.suspendSession(sessionId)
      if (!suspendResult.success) {
        socket.emit('suspend_fail', suspendResult.error)
        return
      }

      // 解绑socket，但保持SSH连接
      sessionManager.unbindSocket(socket.id)

      // 重新绑定stream的data事件用于缓存输出
      session.stream.removeAllListeners('data')
      session.stream.on('data', (data) => {
        session.appendOutput(data)
      })

      // 监听SSH连接关闭事件（挂起期间SSH断开）
      session.sshClient.once('close', () => {
        if (session.status === SessionStatus.SUSPENDED) {
          logger.warn(`挂起会话 ${ sessionId } 的SSH连接已断开`)
          session.appendOutput('\r\n\x1b[91m═══ SSH连接已断开 ═══\x1b[0m\r\n')
        }
      })

      session.sshClient.once('error', (err) => {
        if (session.status === SessionStatus.SUSPENDED) {
          logger.error(`挂起会话 ${ sessionId } SSH错误: ${ err.message }`)
          session.appendOutput(`\r\n\x1b[91m═══ SSH错误: ${ err.message } ═══\x1b[0m\r\n`)
        }
      })

      socket.emit('terminal_suspended', {
        sessionId,
        hostId: session.hostId
      })

      logger.info(`终端已挂起: ${ sessionId }`)
    })

    // 获取挂起的会话列表
    socket.on('get_suspended_sessions', async ({ hostId } = {}) => {
      const sessions = sessionManager.getSuspendedSessions(userId, hostId)

      // 补充主机名信息
      const sessionsWithHostInfo = await Promise.all(
        sessions.map(async (s) => {
          const hostInfo = await hostListDB.findOneAsync({ _id: s.hostId })
          return {
            ...s,
            hostName: hostInfo?.name || '未知主机',
            host: hostInfo?.host || ''
          }
        })
      )

      socket.emit('suspended_sessions_list', sessionsWithHostInfo)
    })

    // 销毁挂起的会话（不恢复，直接关闭）
    socket.on('destroy_suspended_session', ({ sessionId }) => {
      const session = sessionManager.getSession(sessionId)
      if (!session) {
        socket.emit('destroy_session_fail', '会话不存在')
        return
      }

      if (session.userId !== userId) {
        socket.emit('destroy_session_fail', '无权操作此会话')
        return
      }

      if (session.status !== SessionStatus.SUSPENDED) {
        socket.emit('destroy_session_fail', '只能销毁挂起状态的会话')
        return
      }

      sessionManager.destroySession(sessionId)
      socket.emit('session_destroyed', { sessionId })
      logger.info(`挂起会话已销毁: ${ sessionId }`)
    })

    // ping检测
    socket.on('get_ping', async (ip) => {
      try {
        socket.emit('ping_data', await ping(ip, 2500))
      } catch (error) {
        socket.emit('ping_data', { success: false, msg: error.message })
      }
    })

    // 断开连接处理
    socket.on('disconnect', (reason) => {
      connectionCount--

      // 检查是否有关联的会话
      const session = sessionManager.getSessionBySocket(socket.id)
      if (session) {
        if (session.status === SessionStatus.SUSPENDED) {
          // 已挂起的会话，保持SSH连接
          logger.info(`会话 ${ session.sessionId } 已挂起，保持SSH连接`)
        } else {
          // 未挂起的会话，正常销毁
          sessionManager.destroySession(session.sessionId)
        }
        sessionManager.unbindSocket(socket.id)
      }

      logger.info(`终端socket连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}

module.exports = (httpServer) => {
  const serverIo = createSecureWs(httpServer, '/terminal')
  createServerIo(serverIo)
}

module.exports.getConnectionOptions = getConnectionOptions
module.exports.createTerminal = createTerminal
module.exports.createServerIo = createServerIo
module.exports.getProxyConfig = getProxyConfig
module.exports.handleProxyAndJumpHostConnection = handleProxyAndJumpHostConnection
