/**
 * 终端会话管理器
 */

// 会话状态枚举
const SessionStatus = {
  ACTIVE: 'active', // 前端已连接，正常使用中
  SUSPENDED: 'suspended', // 已挂起，SSH保持但无前端连接
  EXPIRED: 'expired' // 已过期，待清理
}

// 默认配置（统一配置来源）
const DEFAULT_SESSION_CONFIG = {
  maxSuspendTime: 24, // 小时
  maxSuspendedPerUser: 10, // 最大挂起数
  heartbeatInterval: 30, // 秒
  maxReconnectAttempts: 3, // 最大重连次数
  reconnectInterval: 60, // 秒
  maxBufferSize: 50 // KB
}

/**
 * 获取默认配置（供其他模块使用）
 * @returns {Object} 默认配置
 */
function getDefaultSessionConfig() {
  return { ...DEFAULT_SESSION_CONFIG }
}

/**
 * 单个终端会话
 */
class TerminalSession {
  constructor(options) {
    this.sessionId = options.sessionId // 唯一会话ID
    this.hostId = options.hostId // 主机ID
    this.userId = options.userId // 用户ID
    this.sshClient = options.sshClient // SSH2 Client实例
    this.stream = options.stream // SSH Shell Stream
    this.jumpSshClients = options.jumpSshClients || [] // 跳板机连接
    this.status = SessionStatus.ACTIVE
    this.createdAt = Date.now()
    this.suspendedAt = null
    this.outputBuffer = [] // 挂起期间的输出缓存

    // 从options中读取配置，如果没有则使用默认值
    this.maxBufferSize = options.maxBufferSize || 50 * 1024 // 最大缓存（默认50KB）
    this.bufferSize = 0

    // 心跳检测相关（从options中读取配置）
    this.heartbeatInterval = options.heartbeatInterval || 30 * 1000 // 心跳间隔（默认30秒）
    this.heartbeatTimer = null // 心跳定时器
    this.reconnectAttempts = 0 // 当前重连尝试次数
    this.maxReconnectAttempts = options.maxReconnectAttempts || 3 // 最大重连次数（默认3次）
    this.reconnectInterval = options.reconnectInterval || 60 * 1000 // 重连间隔（默认60秒）
    this.reconnectTimer = null // 重连定时器
    this.lastHeartbeatAt = Date.now() // 最后一次心跳成功时间
    this.connectionAlive = true // 连接是否存活

    // 保存连接配置，用于重连
    this.connectionOptions = options.connectionOptions || null
  }

  /**
   * 追加输出到缓存
   * @param {Buffer|string} data - 输出数据
   */
  appendOutput(data) {
    if (this.status !== SessionStatus.SUSPENDED) return

    const str = data.toString()
    this.bufferSize += str.length

    // 超出最大缓存，移除最早的数据
    while (this.bufferSize > this.maxBufferSize && this.outputBuffer.length > 0) {
      const removed = this.outputBuffer.shift()
      this.bufferSize -= removed.length
    }

    this.outputBuffer.push(str)
  }

  /**
   * 获取并清空缓存
   * @returns {string} 缓存的输出内容
   */
  flushBuffer() {
    const output = this.outputBuffer.join('')
    this.outputBuffer = []
    this.bufferSize = 0
    return output
  }

  /**
   * 启动心跳检测（挂起时调用）
   */
  startHeartbeat() {
    this.stopHeartbeat()
    this.heartbeatTimer = setInterval(() => {
      this.checkConnection()
    }, this.heartbeatInterval)
    logger.info(`会话 ${ this.sessionId } 心跳检测已启动`)
  }

  /**
   * 停止心跳检测（恢复或销毁时调用）
   */
  stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = null
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  /**
   * 检测连接状态
   */
  checkConnection() {
    if (!this.sshClient || !this.sshClient._sock || !this.sshClient._sock.writable) {
      logger.warn(`会话 ${ this.sessionId } 心跳检测失败，SSH连接已断开`)
      this.connectionAlive = false
      this.handleConnectionLost()
      return
    }

    // 发送一个空操作来检测连接（SSH keepalive）
    try {
      this.sshClient._sock.write('')
      this.lastHeartbeatAt = Date.now()
      this.connectionAlive = true
      this.reconnectAttempts = 0 // 重置重连计数
    } catch (err) {
      logger.warn(`会话 ${ this.sessionId } 心跳发送失败: ${ err.message }`)
      this.connectionAlive = false
      this.handleConnectionLost()
    }
  }

  /**
   * 处理连接断开
   */
  handleConnectionLost() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      // 已达到最大重连次数，标记会话为断开
      logger.error(`会话 ${ this.sessionId } 重连失败已达 ${ this.maxReconnectAttempts } 次，标记为断开`)
      this.status = SessionStatus.EXPIRED
      this.stopHeartbeat()
      this.appendOutput('\r\n\x1b[91m═══ SSH连接已断开，自动重连失败 ═══\x1b[0m\r\n')
      return
    }

    this.reconnectAttempts++
    logger.info(`会话 ${ this.sessionId } 将在 ${ this.reconnectInterval / 1000 } 秒后尝试第 ${ this.reconnectAttempts } 次重连`)

    // 缓存重连提示
    this.appendOutput(`\r\n\x1b[93m═══ SSH连接断开，${ this.reconnectInterval / 1000 }秒后尝试第${ this.reconnectAttempts }次重连 ═══\x1b[0m\r\n`)

    // 设置延迟重连
    this.reconnectTimer = setTimeout(() => {
      this.attemptReconnect()
    }, this.reconnectInterval)
  }

  /**
   * 尝试重新连接
   */
  async attemptReconnect() {
    logger.info(`会话 ${ this.sessionId } 开始第 ${ this.reconnectAttempts } 次重连`)

    try {
      // 关闭旧连接
      if (this.stream) {
        this.stream.removeAllListeners()
        try {
          this.stream.close()
        } catch (e) {
          // 忽略关闭错误
        }
      }
      if (this.sshClient) {
        this.sshClient.removeAllListeners()
        try {
          this.sshClient.end()
        } catch (e) {
          // 忽略关闭错误
        }
      }

      // 如果没有连接配置，无法重连
      if (!this.connectionOptions) {
        logger.error(`会话 ${ this.sessionId } 没有保存连接配置，无法重连`)
        this.status = SessionStatus.EXPIRED
        this.stopHeartbeat()
        this.appendOutput('\r\n\x1b[91m═══ 无法重连：缺少连接配置 ═══\x1b[0m\r\n')
        return
      }

      // 创建新的SSH连接
      const { Client: SSHClient } = require('ssh2')
      const newClient = new SSHClient()

      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('连接超时'))
        }, 30000)

        newClient.on('ready', () => {
          clearTimeout(timeout)
          resolve()
        })

        newClient.on('error', (err) => {
          clearTimeout(timeout)
          reject(err)
        })

        newClient.connect(this.connectionOptions)
      })

      // 创建新的shell
      const newStream = await new Promise((resolve, reject) => {
        newClient.shell({ term: 'xterm-color' }, (err, stream) => {
          if (err) reject(err)
          else resolve(stream)
        })
      })

      // 更新会话
      this.sshClient = newClient
      this.stream = newStream
      this.connectionAlive = true
      this.reconnectAttempts = 0
      this.lastHeartbeatAt = Date.now()

      // 重新绑定输出缓存
      newStream.on('data', (data) => {
        this.appendOutput(data)
      })

      // 监听连接关闭
      newClient.on('close', () => {
        if (this.status === SessionStatus.SUSPENDED) {
          this.connectionAlive = false
          this.handleConnectionLost()
        }
      })

      newClient.on('error', (err) => {
        logger.error(`会话 ${ this.sessionId } SSH错误: ${ err.message }`)
        if (this.status === SessionStatus.SUSPENDED) {
          this.connectionAlive = false
          this.handleConnectionLost()
        }
      })

      logger.info(`会话 ${ this.sessionId } 重连成功`)
      this.appendOutput('\r\n\x1b[92m═══ SSH连接已恢复 ═══\x1b[0m\r\n')

    } catch (err) {
      logger.error(`会话 ${ this.sessionId } 重连失败: ${ err.message }`)
      this.handleConnectionLost()
    }
  }
}

/**
 * 会话管理器 (单例)
 */
class SessionManager {
  constructor() {
    this.sessions = new Map() // sessionId -> TerminalSession
    this.userSessions = new Map() // `${userId}` -> Set<sessionId> (用户的所有会话)
    this.socketSessionMap = new Map() // socketId -> sessionId

    // 使用统一的默认配置（会从数据库加载覆盖）
    this.maxSuspendTime = DEFAULT_SESSION_CONFIG.maxSuspendTime * 60 * 60 * 1000 // 转换为毫秒
    this.cleanupInterval = 5 * 60 * 1000 // 清理间隔：5分钟
    this.maxSuspendedPerUser = DEFAULT_SESSION_CONFIG.maxSuspendedPerUser
    this.heartbeatInterval = DEFAULT_SESSION_CONFIG.heartbeatInterval * 1000 // 转换为毫秒
    this.maxReconnectAttempts = DEFAULT_SESSION_CONFIG.maxReconnectAttempts
    this.reconnectInterval = DEFAULT_SESSION_CONFIG.reconnectInterval * 1000 // 转换为毫秒
    this.maxBufferSize = DEFAULT_SESSION_CONFIG.maxBufferSize * 1024 // 转换为字节

    this.initialized = false // 标记是否已从数据库加载配置

    this.startCleanupTimer()
    // 异步加载配置（不阻塞构造函数）
    this.loadConfigFromDB().catch(err => {
      logger.warn('从数据库加载终端会话配置失败，使用默认配置:', err.message)
    })
  }

  /**
   * 从数据库加载配置
   */
  async loadConfigFromDB() {
    try {
      const { TerminalSessionDB } = require('./db-class')
      const terminalSessionDB = new TerminalSessionDB().getInstance()
      const config = await terminalSessionDB.findOneAsync({})

      if (config) {
        // 加载所有配置字段
        if (config.maxSuspendTime !== undefined) {
          // 数据库中存储的是小时，需要转换为毫秒
          this.maxSuspendTime = config.maxSuspendTime * 60 * 60 * 1000
        }
        if (config.maxSuspendedPerUser !== undefined) {
          this.maxSuspendedPerUser = config.maxSuspendedPerUser
        }
        if (config.heartbeatInterval !== undefined) {
          // 数据库中存储的是秒，需要转换为毫秒
          this.heartbeatInterval = config.heartbeatInterval * 1000
        }
        if (config.maxReconnectAttempts !== undefined) {
          this.maxReconnectAttempts = config.maxReconnectAttempts
        }
        if (config.reconnectInterval !== undefined) {
          // 数据库中存储的是秒，需要转换为毫秒
          this.reconnectInterval = config.reconnectInterval * 1000
        }
        if (config.maxBufferSize !== undefined) {
          // 数据库中存储的是KB，需要转换为字节
          this.maxBufferSize = config.maxBufferSize * 1024
        }
        logger.info(`已从数据库加载终端会话配置: maxSuspendedPerUser=${this.maxSuspendedPerUser}, maxSuspendTime=${this.maxSuspendTime / 1000 / 60 / 60}小时`)
      } else {
        logger.info('数据库中无终端会话配置，使用默认配置')
      }
      this.initialized = true
    } catch (error) {
      logger.error('loadConfigFromDB error:', error.message)
      this.initialized = true // 即使失败也标记为已初始化，使用默认值
    }
  }

  /**
   * 生成会话ID
   * @param {string} userId - 用户ID
   * @param {string} hostId - 主机ID
   * @returns {string} 会话ID
   */
  generateSessionId(userId, hostId) {
    return `${ userId }-${ hostId }-${ Date.now() }-${ Math.random().toString(36).substr(2, 9) }`
  }

  /**
   * 获取用户当前挂起会话数量
   * @param {string} userId - 用户ID
   * @returns {number} 挂起会话数量
   */
  getUserSuspendedCount(userId) {
    let count = 0
    for (const [, session] of this.sessions) {
      if (session.userId === userId && session.status === SessionStatus.SUSPENDED) {
        count++
      }
    }
    return count
  }

  /**
   * 创建会话
   * @param {Object} options - 会话选项
   * @returns {TerminalSession} 创建的会话
   */
  createSession(options) {
    const sessionId = this.generateSessionId(options.userId, options.hostId)

    // 将SessionManager的配置传递给TerminalSession
    const sessionOptions = {
      ...options,
      sessionId,
      heartbeatInterval: this.heartbeatInterval,
      maxReconnectAttempts: this.maxReconnectAttempts,
      reconnectInterval: this.reconnectInterval,
      maxBufferSize: this.maxBufferSize
    }

    const session = new TerminalSession(sessionOptions)

    this.sessions.set(sessionId, session)

    // 维护用户会话集合
    if (!this.userSessions.has(options.userId)) {
      this.userSessions.set(options.userId, new Set())
    }
    this.userSessions.get(options.userId).add(sessionId)

    logger.info(`会话已创建: ${ sessionId }`)
    return session
  }

  /**
   * 获取会话
   * @param {string} sessionId - 会话ID
   * @returns {TerminalSession|undefined} 会话实例
   */
  getSession(sessionId) {
    return this.sessions.get(sessionId)
  }

  /**
   * 通过socket获取会话
   * @param {string} socketId - Socket ID
   * @returns {TerminalSession|undefined} 会话实例
   */
  getSessionBySocket(socketId) {
    const sessionId = this.socketSessionMap.get(socketId)
    return sessionId ? this.sessions.get(sessionId) : null
  }

  /**
   * 查找用户对某主机的挂起会话（返回最近挂起的一个）
   * @param {string} userId - 用户ID
   * @param {string} hostId - 主机ID
   * @returns {TerminalSession|null} 挂起的会话
   */
  findSuspendedSession(userId, hostId) {
    let latestSession = null
    let latestSuspendedAt = 0

    for (const [, session] of this.sessions) {
      if (session.userId === userId &&
          session.hostId === hostId &&
          session.status === SessionStatus.SUSPENDED) {
        // 返回最近挂起的会话
        if (session.suspendedAt > latestSuspendedAt) {
          latestSuspendedAt = session.suspendedAt
          latestSession = session
        }
      }
    }
    return latestSession
  }

  /**
   * 绑定socket与会话
   * @param {string} socketId - Socket ID
   * @param {string} sessionId - 会话ID
   */
  bindSocket(socketId, sessionId) {
    this.socketSessionMap.set(socketId, sessionId)
  }

  /**
   * 解绑socket
   * @param {string} socketId - Socket ID
   */
  unbindSocket(socketId) {
    this.socketSessionMap.delete(socketId)
  }

  /**
   * 挂起会话（带用户挂起数量限制检查）
   * @param {string} sessionId - 会话ID
   * @returns {Object} 操作结果 { success: boolean, error?: string }
   */
  suspendSession(sessionId) {
    const session = this.sessions.get(sessionId)
    if (!session) return { success: false, error: '会话不存在' }

    // 检查用户挂起会话数量限制
    // 注意：此时当前会话状态仍为ACTIVE，所以不会被计入挂起数量
    // 因此需要检查 currentSuspendedCount + 1 是否会超过限制
    const currentSuspendedCount = this.getUserSuspendedCount(session.userId)
    if (currentSuspendedCount >= this.maxSuspendedPerUser) {
      return {
        success: false,
        error: `已达到最大挂起数量限制(${ this.maxSuspendedPerUser }个)，请先恢复或关闭其他挂起的会话`
      }
    }

    session.status = SessionStatus.SUSPENDED
    session.suspendedAt = Date.now()

    // 启动心跳检测
    session.startHeartbeat()

    logger.info(`会话已挂起: ${ sessionId }`)
    return { success: true }
  }

  /**
   * 恢复会话（带SSH连接状态检查）
   * @param {string} sessionId - 会话ID
   * @returns {TerminalSession|null} 恢复的会话，失败返回null
   */
  resumeSession(sessionId) {
    const session = this.sessions.get(sessionId)
    if (!session || session.status !== SessionStatus.SUSPENDED) return null

    // 停止心跳检测
    session.stopHeartbeat()

    // 检查SSH连接是否仍然有效
    if (!session.sshClient || !session.sshClient._sock || !session.sshClient._sock.writable) {
      logger.warn(`会话 ${ sessionId } 的SSH连接已断开，无法恢复`)
      // 标记为过期，等待清理
      session.status = SessionStatus.EXPIRED
      return null
    }

    session.status = SessionStatus.ACTIVE
    session.suspendedAt = null
    session.reconnectAttempts = 0

    logger.info(`会话已恢复: ${ sessionId }`)
    return session
  }

  /**
   * 销毁会话
   * @param {string} sessionId - 会话ID
   */
  destroySession(sessionId) {
    const session = this.sessions.get(sessionId)
    if (!session) return

    // 停止心跳检测
    session.stopHeartbeat()

    // 关闭SSH连接
    if (session.stream) {
      try {
        session.stream.close()
      } catch (e) {
        // 忽略关闭错误
      }
    }
    if (session.sshClient) {
      try {
        session.sshClient.end()
      } catch (e) {
        // 忽略关闭错误
      }
    }
    // 关闭跳板机连接
    session.jumpSshClients?.forEach(client => {
      try {
        client?.end()
      } catch (e) {
        // 忽略关闭错误
      }
    })

    // 清理用户会话集合
    const userSessionSet = this.userSessions.get(session.userId)
    if (userSessionSet) {
      userSessionSet.delete(sessionId)
      if (userSessionSet.size === 0) {
        this.userSessions.delete(session.userId)
      }
    }
    this.sessions.delete(sessionId)

    logger.info(`会话已销毁: ${ sessionId }`)
  }

  /**
   * 获取用户的挂起会话列表
   * @param {string} userId - 用户ID
   * @param {string|null} hostId - 可选的主机ID过滤
   * @returns {Array} 挂起会话列表
   */
  getSuspendedSessions(userId, hostId = null) {
    const result = []
    for (const [sessionId, session] of this.sessions) {
      if (session.userId !== userId) continue
      if (session.status !== SessionStatus.SUSPENDED) continue
      if (hostId && session.hostId !== hostId) continue

      result.push({
        sessionId,
        hostId: session.hostId,
        suspendedAt: session.suspendedAt,
        createdAt: session.createdAt,
        connectionAlive: session.connectionAlive
      })
    }
    return result
  }

  /**
   * 定时清理过期会话
   */
  startCleanupTimer() {
    setInterval(() => {
      const now = Date.now()
      for (const [sessionId, session] of this.sessions) {
        if (session.status === SessionStatus.SUSPENDED) {
          const suspendDuration = now - session.suspendedAt
          if (suspendDuration > this.maxSuspendTime) {
            logger.info(`会话 ${ sessionId } 挂起超时 (${ Math.round(suspendDuration / 1000 / 60) }分钟)，自动销毁`)
            this.destroySession(sessionId)
          }
        }
        // 清理已过期的会话（重连失败的）
        if (session.status === SessionStatus.EXPIRED) {
          logger.info(`会话 ${ sessionId } 已过期，清理资源`)
          this.destroySession(sessionId)
        }
      }
    }, this.cleanupInterval)
  }

  /**
   * 获取统计信息（用于调试）
   * @returns {Object} 统计信息
   */
  getStats() {
    let activeCount = 0
    let suspendedCount = 0
    let expiredCount = 0

    for (const [, session] of this.sessions) {
      switch (session.status) {
        case SessionStatus.ACTIVE:
          activeCount++
          break
        case SessionStatus.SUSPENDED:
          suspendedCount++
          break
        case SessionStatus.EXPIRED:
          expiredCount++
          break
      }
    }

    return {
      total: this.sessions.size,
      active: activeCount,
      suspended: suspendedCount,
      expired: expiredCount,
      socketBindings: this.socketSessionMap.size
    }
  }
}

// 导出单例
const sessionManager = new SessionManager()

module.exports = {
  SessionStatus,
  TerminalSession,
  sessionManager,
  getDefaultSessionConfig
}
