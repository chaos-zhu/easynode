/**
 * Agent 的 WebSocket 通道
 *
 * 复用 createSecureWs 的统一鉴权，与 /terminal、/sftp-v2 等保持一致。
 *
 * 客户端 → 服务端：
 *   ws_agent_run      发起一个 turn { sessionId?, input, modelId, permission, hostIds }
 *                     只发本轮输入，历史由后端持有
 *   ws_agent_approve  回传审批结果 { requestId, approved, scope }
 *   ws_agent_stop     中断当前 turn
 *
 * 服务端 → 客户端：统一用 agent_event 事件，payload.type 区分种类。
 * 单一事件通道比十几个具名事件更好维护，前端一个 switch 就能分发。
 */

import { createSecureWs } from '../utils/ws-tool.js'
import { parseCookies } from '../utils/verify-auth.js'
import { getClientIP } from '../utils/tools.js'
import { RuntimeState } from '../utils/runtime-state.js'
import { runTurn } from '../ai/runtime.js'
import { resolveApproval, clearSession, listPending } from '../ai/approval.js'
import { clearBySession } from '../ai/output-store.js'
import { disconnect as disconnectHost } from '../ai/ssh.js'
import { PRESETS, DEFAULT_PRESET } from '../ai/policy.js'
import { listConfiguredModels } from '../ai/provider.js'
import { TOOL_SPECS } from '../ai/tools/spec.js'
// 会话的读取走 REST（controller/agent-session.js），socket 只负责跑 turn。
// 同一件事只留一条路径，避免两边行为漂移。
import { createSession, getSession, appendTurn } from '../ai/session-store.js'
import { resolveTerminalDispatch, reportTerminalDispatchProgress, clearTerminalDispatchBySession } from '../ai/terminal-dispatch.js'
import { claimSessionRun, releaseSessionRun } from '../ai/session-run-lock.js'

const runtimeState = new RuntimeState().getInstance()

/** Plus 是否可用，判定方式与 utils/decrypt-file.js 保持一致 */
function isPlusAvailable() {
  return Boolean(runtimeState.getDecryptKey()) && !runtimeState.getPlusKicked()
}

/**
 * 审计用的操作者标识。
 *
 * verifyWsAuthSync 只做校验、不往 socket 上挂用户信息，而 easynode 是
 * 单用户面板，所以用 session 前缀 + 客户端 IP 作为操作者标识 —— 事后
 * 至少能对上是哪个登录会话、从哪个 IP 发起的。
 */
function resolveOperator(socket) {
  const ip = getClientIP(socket.conn.remoteAddress, socket.handshake.headers['x-forwarded-for'])
  const { session } = parseCookies(socket.handshake.headers.cookie || '')
  const sessionTag = session ? String(session).slice(0, 8) : 'unknown'
  return `${ sessionTag }@${ ip }`
}

/** socket.id -> { controller, sessionId, running } */
const active = new Map()
const starting = new Set()

function createEmitter(socket) {
  return (payload) => {
    if (socket.disconnected) return
    socket.emit('agent_event', payload)
  }
}

/** 断开该会话用过的 agent SSH 连接 */
function releaseHosts(hostIds) {
  for (const hostId of hostIds || []) disconnectHost(hostId)
}

function abortActive(socketId) {
  const entry = active.get(socketId)
  if (!entry) return
  try {
    entry.controller.abort()
  } catch {
    // 忽略
  }
}

export default (httpServer) => {
  const serverIo = createSecureWs(httpServer, '/ai-agent')

  serverIo.on('connection', (socket) => {
    const operator = resolveOperator(socket)
    logger.info(`ai-agent websocket 已连接: ${ operator }`)
    const emit = createEmitter(socket)

    // 连接建立后先告诉前端可用的模型与权限预设，避免前端再发一轮 HTTP
    listConfiguredModels()
      .then((config) => {
        emit({
          type: 'ready',
          models: config.models,
          defaultModel: config.defaultModel,
          presets: Object.values(PRESETS).map(({ key, label, desc }) => ({ key, label, desc })),
          defaultPreset: DEFAULT_PRESET,
          plusAvailable: isPlusAvailable(),
          tools: TOOL_SPECS.map(({
            name, effect, plusPolicy, description
          }) => ({
            name,
            effect,
            plusPolicy,
            description
          }))
        })
      })
      .catch((error) => emit({ type: 'error', message: error.message }))

    socket.on('ws_agent_run', async (payload = {}) => {
      const { input, modelId, permission, hostIds, hostId, terminalContext, terminalPermission } = payload
      const scope = payload.scope === 'terminal' ? 'terminal' : 'ops'
      // 目标主机必须由本次请求显式携带。不能在空数组或缺省时回退到
      // 历史会话的 hostIds，否则用户取消选择主机后仍可能继续操作旧主机。
      const selectedHostIds = Array.isArray(hostIds) ? hostIds : []

      if (active.get(socket.id)?.running || starting.has(socket.id)) {
        return emit({ type: 'error', message: '当前会话仍有任务在执行，请先停止' })
      }
      if (!input || typeof input !== 'string' || !input.trim()) {
        return emit({ type: 'error', message: '消息内容不能为空' })
      }

      starting.add(socket.id)
      let session
      try {
        // 会话由后端持有：前端只发本轮输入，历史不经过网络来回搬，
        // 也就不存在前端改写历史绕过权限的可能
        session = payload.sessionId ? await getSession(payload.sessionId) : null
        if (session && (session.scope || 'ops') !== scope) {
          starting.delete(socket.id)
          return emit({ type: 'error', message: '不能在不同类型的 AI 会话之间混用历史' })
        }
        if (scope === 'terminal' && (!hostId || !terminalContext || typeof terminalContext.output !== 'string' || terminalContext.output.length > 16 * 1024 || selectedHostIds.length !== 1 || selectedHostIds[0] !== hostId)) {
          starting.delete(socket.id)
          return emit({ type: 'error', message: '终端 AI 缺少当前终端上下文或目标主机' })
        }
        if (session && scope === 'terminal' && session.hostId !== hostId) {
          starting.delete(socket.id)
          return emit({ type: 'error', message: '当前终端与历史会话主机不一致' })
        }
        if (!session) {
          session = await createSession({
            hostIds: selectedHostIds,
            modelId,
            permission: permission || DEFAULT_PRESET,
            scope,
            hostId: scope === 'terminal' ? hostId : ''
          })
          emit({ type: 'session_created', session: { id: session.id, title: session.title } })
        }
      } catch (error) {
        starting.delete(socket.id)
        return emit({ type: 'error', message: `会话初始化失败: ${ error.message }` })
      }

      if (socket.disconnected) {
        starting.delete(socket.id)
        return
      }
      if (!claimSessionRun(session.id, socket.id)) {
        starting.delete(socket.id)
        return emit({ type: 'error', message: '该会话正在其他客户端执行，请稍后再试' })
      }

      const controller = new AbortController()
      const targetHosts = selectedHostIds
      active.set(socket.id, { controller, sessionId: session.id, running: true, hostIds: targetHosts, scope })
      starting.delete(socket.id)

      // 前端重连后把仍在挂起的审批重放一遍，否则用户看不到待确认项
      const pendingApprovals = listPending(session.id)
      if (pendingApprovals.length) {
        emit({ type: 'pending_approvals', items: pendingApprovals })
      }

      const turnCreatedAt = Date.now()
      const userMessage = { role: 'user', content: input }
      let turnResult = null

      try {
        // 历史的读取（含按需压缩）由 runtime 负责 —— 压缩要用到模型，
        // 而模型是 runtime 解析的，放在这里会多解析一次、也容易两处不一致。
        // 写入仍由本层负责，见 finally 里的 appendTurn。
        turnResult = await runTurn({
          sessionId: session.id,
          userId: operator,
          userMessage,
          modelId: modelId || session.modelId,
          permission: permission || session.permission || DEFAULT_PRESET,
          hostIds: selectedHostIds,
          scope,
          terminalHostId: scope === 'terminal' ? hostId : undefined,
          terminalPermission: scope === 'terminal' ? terminalPermission : undefined,
          terminalContext: scope === 'terminal' ? terminalContext : undefined,
          signal: controller.signal,
          emit
        })
      } catch (error) {
        logger.error(`[ai-agent] turn 失败: ${ error.message }`)
        emit({ type: 'error', message: error.message })
      } finally {
        // 即使 turn 失败或被中断也要落盘：用户的输入不能丢，
        // 已产生的工具调用也必须连同结果一起存，否则历史会残缺
        try {
          const saved = await appendTurn(session.id, {
            newMessages: [userMessage, ...(turnResult?.responseMessages || [])],
            createdAt: turnCreatedAt,
            toolMeta: turnResult?.toolMeta,
            usage: turnResult?.usage
          })
          emit({
            type: 'session_saved',
            session: { id: saved.id, title: saved.title, usage: saved.usage, updatedAt: saved.updatedAt }
          })
        } catch (error) {
          logger.error(`[ai-agent] 会话落盘失败: ${ error.message }`)
        }

        const entry = active.get(socket.id)
        if (entry?.controller === controller) active.delete(socket.id)
        releaseSessionRun(session.id, socket.id)
      }
    })

    socket.on('ws_agent_approve', (payload = {}) => {
      const { requestId, approved, scope } = payload
      if (!requestId) return emit({ type: 'error', message: '缺少 requestId' })
      const result = resolveApproval(requestId, { approved, scope })
      if (!result.ok) emit({ type: 'error', message: result.error })
    })

    socket.on('ws_agent_stop', () => {
      abortActive(socket.id)
      emit({ type: 'stopped' })
    })

    socket.on('ws_terminal_command_result', (payload = {}) => {
      const result = resolveTerminalDispatch(payload.requestId, payload)
      if (!result.ok) emit({ type: 'error', message: result.error })
    })

    socket.on('ws_terminal_command_progress', (payload = {}) => {
      reportTerminalDispatchProgress(payload.requestId, payload)
    })

    socket.on('disconnect', () => {
      starting.delete(socket.id)
      const entry = active.get(socket.id)
      abortActive(socket.id)
      if (entry?.sessionId) {
        clearSession(entry.sessionId)
        clearTerminalDispatchBySession(entry.sessionId)
        clearBySession(entry.sessionId)
      }
      // agent 建立的 SSH 连接虽有空闲超时兜底，但用户关掉面板后没必要
      // 再占着连接，主动断开
      if (entry?.scope !== 'terminal') releaseHosts(entry?.hostIds)
      logger.info('ai-agent websocket 已断开')
    })
  })
}
