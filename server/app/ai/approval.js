/**
 * 审批网关
 *
 * 模型要执行写操作时在这里挂起，等前端点"允许"或"拒绝"。
 *
 * 两个必须有的东西：
 *   1. 超时 —— 用户关掉页面就再也不点了，没有超时会导致这个 turn 永久挂起，
 *      SSH 连接和 socket 一起泄漏
 *   2. 会话级授权记忆 —— 连续十次 `docker restart` 弹十次窗，用户会直接切到
 *      授权模式。对可稳定指纹化的普通操作允许“本次会话都允许”。
 */

import { randomUUID } from 'node:crypto'
import { writeAudit, ACTION } from './audit.js'
import { parseCommandLine, unwrapCommand } from './shell-lexer.js'

// 前端不响应时的兜底时长
export const APPROVAL_TIMEOUT_MS = 5 * 60 * 1000

/** requestId -> { resolve, timer, sessionId } */
const pending = new Map()
/** sessionId -> Set<grantKey> */
const sessionGrants = new Map()

/**
 * 授权记忆的粒度。
 *
 * 之前只用工具名（write_file 批准一次 = 任意主机任意路径）或命令前两个词
 * （批准 `rm -rf /tmp/x` 后 `rm -rf /` 同样命中）—— 范围大到失去意义。
 *
 * exec_command 采用显式白名单：只有能够稳定描述“动作 + 完整对象”的少数
 * 服务操作才允许复用。文件变更、动态/复合命令和无法可靠归一化的命令一律
 * 只能单次批准，避免一次 `rm` 授权扩散成同主机上的任意删除。
 */
export function sessionGrantScope(toolName, input) {
  const hostId = input?.hostId || 'any'

  if (toolName === 'exec_command') {
    const segments = parseCommandLine(String(input?.command || ''))
    if (segments.length !== 1 || segments[0].dynamic || segments[0].redirects.length) return null
    const first = segments[0]
    const { cmd, args } = unwrapCommand(first.argv)
    let action = ''
    let objects = []

    if (cmd === 'systemctl') {
      action = args.find((arg) => !arg.startsWith('-')) || ''
      if (!['start', 'restart', 'reload', 'try-restart'].includes(action)) return null
      const actionIndex = args.indexOf(action)
      objects = args.slice(actionIndex + 1).filter((arg) => !arg.startsWith('-'))
    } else if (cmd === 'service') {
      if (args.length < 2 || !['start', 'restart', 'reload'].includes(args[1])) return null
      objects = [args[0]]
      action = args[1]
    } else if (cmd === 'rc-service') {
      if (args.length < 2 || !['start', 'restart', 'reload'].includes(args[1])) return null
      objects = [args[0]]
      action = args[1]
    } else if (cmd === 'docker' || cmd === 'podman') {
      action = args.find((arg) => !arg.startsWith('-')) || ''
      if (!['start', 'restart'].includes(action)) return null
      const actionIndex = args.indexOf(action)
      objects = args.slice(actionIndex + 1).filter((arg) => !arg.startsWith('-'))
    } else {
      return null
    }

    if (!objects.length) return null
    // key 保留完整参数（包括选项），同一对象但执行语义不同的命令不能共享授权。
    const fingerprint = [cmd, ...args].map((item) => encodeURIComponent(item)).join(':')
    return {
      key: `${ toolName }:${ hostId }:${ fingerprint }`,
      label: `${ cmd } ${ args.join(' ') }`
    }
  }

  return null
}

/** 供测试与诊断检查授权指纹；不可授权时返回空字符串。 */
export function grantKey(toolName, input) {
  return sessionGrantScope(toolName, input)?.key || ''
}

export function hasSessionGrant(sessionId, key) {
  return Boolean(sessionGrants.get(sessionId)?.has(key))
}

function addSessionGrant(sessionId, key) {
  if (!sessionGrants.has(sessionId)) sessionGrants.set(sessionId, new Set())
  sessionGrants.get(sessionId).add(key)
}

/**
 * 发起一次审批请求
 *
 * @param {object} params
 * @param {string} params.sessionId
 * @param {string} params.toolName
 * @param {string} [params.toolCallId]
 * @param {object} params.input 工具入参
 * @param {object} [params.risk] safety.js 的判定结果摘要
 * @param {string} [params.hostName]
 * @param {(payload: object) => void} params.emit 推送给前端的函数
 * @param {AbortSignal} [params.signal]
 * @returns {Promise<{ approved: boolean, scope: 'once'|'session', reason?: string }>}
 */
export function requestApproval(params) {
  const {
    sessionId,
    toolName,
    toolCallId,
    input,
    risk,
    riskLevel,
    mode,
    effect,
    targets,
    hostName,
    preview,
    sensitiveDisclosure,
    emit,
    signal,
    grantable: sessionGrantable = true
  } = params
  const scope = sessionGrantable && riskLevel !== 'high'
    ? sessionGrantScope(toolName, input)
    : null
  const key = scope?.key || ''

  // 高危调用不接受会话级授权。
  const grantable = Boolean(scope)

  if (grantable && hasSessionGrant(sessionId, key)) {
    return Promise.resolve({ approved: true, scope: 'session', cached: true })
  }

  const requestId = randomUUID()

  return new Promise((resolve) => {
    const settle = (result) => {
      const entry = pending.get(requestId)
      if (!entry) return
      clearTimeout(entry.timer)
      pending.delete(requestId)
      if (signal && entry.onAbort) signal.removeEventListener('abort', entry.onAbort)
      resolve(result)
    }

    const timer = setTimeout(() => {
      writeAudit({
        action: ACTION.REJECTED,
        sessionId,
        tool: toolName,
        command: input?.command,
        reason: '审批超时，未收到用户响应'
      })
      emit({ type: 'approval_timeout', requestId })
      settle({ approved: false, reason: '等待确认超时，操作已取消' })
    }, APPROVAL_TIMEOUT_MS)

    const onAbort = () => {
      emit({ type: 'approval_cancelled', requestId })
      settle({ approved: false, reason: '用户已停止本次任务' })
    }

    pending.set(requestId, { resolve: settle, timer, sessionId, toolName, key, grantable, onAbort })

    if (signal) {
      if (signal.aborted) return onAbort()
      signal.addEventListener('abort', onAbort, { once: true })
    }

    emit({
      type: 'approval_request',
      requestId,
      sessionId,
      toolCallId,
      tool: toolName,
      input,
      preview,
      hostName,
      mode,
      effect,
      targets: Array.isArray(targets) ? targets : [],
      sensitiveDisclosure: Boolean(sensitiveDisclosure),
      risk: risk ? { level: risk.level || risk.risk, reason: risk.reason, category: risk.category } : null,
      grantKey: key,
      grantLabel: scope?.label,
      // 前端据此决定是否展示"本会话都允许"按钮
      grantable,
      timeoutMs: APPROVAL_TIMEOUT_MS
    })
  })
}

/**
 * 前端回传审批结果
 * @param {string} requestId
 * @param {object} payload
 * @param {boolean} payload.approved
 * @param {'once'|'session'} [payload.scope]
 */
export function resolveApproval(requestId, payload = {}) {
  const entry = pending.get(requestId)
  if (!entry) return { ok: false, error: '该审批请求已失效' }

  const approved = Boolean(payload.approved)
  // 高危调用即使前端传了 session，也只按单次处理 —— 不信任前端的传参
  const scope = payload.scope === 'session' && entry.grantable ? 'session' : 'once'

  if (approved && scope === 'session') {
    addSessionGrant(entry.sessionId, entry.key)
  }

  writeAudit({
    action: approved ? ACTION.APPROVED : ACTION.REJECTED,
    sessionId: entry.sessionId,
    tool: entry.toolName,
    reason: approved ? `用户批准（${ scope === 'session' ? '本会话' : '单次' }）` : '用户拒绝'
  })

  entry.resolve({ approved, scope, reason: approved ? undefined : '用户拒绝了该操作' })
  return { ok: true }
}

/** 会话结束时清理其挂起的审批与授权 */
export function clearSession(sessionId) {
  for (const [requestId, entry] of pending.entries()) {
    if (entry.sessionId !== sessionId) continue
    clearTimeout(entry.timer)
    pending.delete(requestId)
    entry.resolve({ approved: false, reason: '会话已结束' })
  }
  sessionGrants.delete(sessionId)
}

/** 当前挂起的审批数，供前端重连后重放 */
export function listPending(sessionId) {
  return [...pending.entries()]
    .filter(([, entry]) => entry.sessionId === sessionId)
    .map(([requestId, entry]) => ({ requestId, tool: entry.toolName }))
}
