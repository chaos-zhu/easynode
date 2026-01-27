const { sessionManager } = require('../socket/session-manager')
const { KeyDB, HostListDB } = require('../utils/db-class')
const dayjs = require('dayjs')

const keyDB = new KeyDB().getInstance()
const hostListDB = new HostListDB().getInstance()

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
        suspendTime: dayjs(session.suspendedAt).format('YYYY-MM-DD HH:mm:ss'),
        connectionAlive: session.connectionAlive
      }
    })

    res.success({ data: result })
  } catch (error) {
    logger.error('getSuspendedSessions error: ', error.message)
    res.fail({ msg: '获取挂起会话列表失败' })
  }
}

module.exports = {
  getSuspendedSessions
}
