/**
 * Agent 操作审计
 *
 * agent 能在生产机上执行命令，事后必须能回答："这条命令是谁触发的、
 * 在什么权限模式下、是自动放行还是人工批准的"。
 *
 * 走 log4js 全局 logger，落到既有日志体系里，不额外引入存储。
 */

const ACTION = {
  TOOL_CALL: 'tool_call',
  DENIED: 'denied',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  EXEC: 'exec'
}

export { ACTION }

function serialize(record) {
  const parts = [`[ai-audit] ${ record.action }`]
  for (const [key, value] of Object.entries(record)) {
    if (key === 'action' || value === undefined || value === null) continue
    parts.push(`${ key }=${ typeof value === 'string' ? value : JSON.stringify(value) }`)
  }
  return parts.join(' | ')
}

/**
 * @param {object} record
 * @param {string} record.action ACTION 之一
 * @param {string} [record.sessionId] agent 会话 ID
 * @param {string} [record.userId] 触发用户
 * @param {string} [record.hostId]
 * @param {string} [record.hostName]
 * @param {string} [record.tool] 工具名
 * @param {string} [record.command] 原始命令
 * @param {string} [record.executed] 实际下发的命令（含包装）
 * @param {string} [record.mode] 生效执行模式
 * @param {string} [record.effect] 操作类型
 * @param {string} [record.risk] 风险级别
 * @param {string} [record.reason] 拦截/告警原因
 * @param {number} [record.exitCode]
 * @param {number} [record.durationMs]
 */
export function writeAudit(record) {
  const line = serialize(record)
  // 拒绝与人工决策属于安全事件，提到 warn 级别便于检索
  if ([ACTION.DENIED, ACTION.REJECTED].includes(record.action)) {
    logger.warn(line)
    return
  }
  logger.info(line)
}
