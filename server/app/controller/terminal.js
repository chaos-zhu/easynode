const { sessionManager, getDefaultSessionConfig } = require('../utils/terminal-session')
const { KeyDB, HostListDB, TerminalSessionDB } = require('../utils/db-class')

const keyDB = new KeyDB().getInstance()
const hostListDB = new HostListDB().getInstance()
const terminalSessionDB = new TerminalSessionDB().getInstance()

async function getSuspendedSessions({ res }) {
  try {
    const { _id: userId } = await keyDB.findOneAsync({})

    // 从session manager获取挂起的会话列表
    const sessions = sessionManager.getSuspendedSessions(userId)

    // 获取所有host信息，用于显示主机名
    const hosts = await hostListDB.findAsync({})
    const hostMap = new Map(hosts.map(h => [h._id, h]))

    // 组装返回数据
    const result = sessions.map(session => {
      const host = hostMap.get(session.hostId)
      return {
        sessionId: session.sessionId,
        hostId: session.hostId,
        hostName: host ? host.name : '未知主机',
        suspendTime: session.suspendedAt,
        connectionAlive: session.connectionAlive
      }
    })

    res.success({ data: result })
  } catch (error) {
    logger.error('getSuspendedSessions error: ', error.message)
    res.fail({ msg: '获取挂起会话列表失败' })
  }
}

async function getTerminalSessionConfig({ res }) {
  try {
    const config = await terminalSessionDB.findOneAsync({})

    // 如果数据库中没有配置，返回默认配置（从SessionManager获取）
    const resultConfig = config ?? getDefaultSessionConfig()

    res.success({ data: { config: resultConfig } })
  } catch (error) {
    logger.error('getTerminalSessionConfig error: ', error.message)
    res.fail({ msg: '获取终端会话配置失败' })
  }
}

async function updateTerminalSessionConfig({ request, res }) {
  try {
    const { config } = request.body
    if (!config) {
      return res.fail({ msg: '配置信息不能为空' })
    }

    // 先查找是否存在配置
    const existingConfig = await terminalSessionDB.findOneAsync({})

    if (existingConfig) {
      // 更新现有配置
      await terminalSessionDB.updateAsync(
        { _id: existingConfig._id },
        { $set: config }
      )
    } else {
      // 插入新配置
      await terminalSessionDB.insertAsync(config)
    }

    // 更新 session manager 的配置（实时生效）
    if (config.maxSuspendTime !== undefined) {
      // maxSuspendTime 前端传入的是小时，需要转换为毫秒
      sessionManager.maxSuspendTime = config.maxSuspendTime * 60 * 60 * 1000
    }
    if (config.maxSuspendedPerUser !== undefined) {
      sessionManager.maxSuspendedPerUser = config.maxSuspendedPerUser
    }
    if (config.heartbeatInterval !== undefined) {
      // heartbeatInterval 前端传入的是秒，需要转换为毫秒
      sessionManager.heartbeatInterval = config.heartbeatInterval * 1000
    }
    if (config.maxReconnectAttempts !== undefined) {
      sessionManager.maxReconnectAttempts = config.maxReconnectAttempts
    }
    if (config.reconnectInterval !== undefined) {
      // reconnectInterval 前端传入的是秒，需要转换为毫秒
      sessionManager.reconnectInterval = config.reconnectInterval * 1000
    }
    if (config.maxBufferSize !== undefined) {
      // maxBufferSize 前端传入的是KB，需要转换为字节
      sessionManager.maxBufferSize = config.maxBufferSize * 1024
    }

    res.success({ msg: '保存成功' })
  } catch (error) {
    logger.error('updateTerminalSessionConfig error: ', error.message)
    res.fail({ msg: '保存终端会话配置失败' })
  }
}

module.exports = {
  getSuspendedSessions,
  getTerminalSessionConfig,
  updateTerminalSessionConfig
}
