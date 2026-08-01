/**
 * Agent 会话：socket 生命周期 + 状态
 *
 * 会话历史由后端持有，前端每次只发本轮输入。所以这里的 messages 是
 * 渲染副本，不是发给模型的真值 —— 不要试图从它反推请求体。
 */

import { reactive, ref, computed, onBeforeUnmount } from 'vue'
import { generateSocketInstance } from '@/utils'
import $api from '@/api'
import {
  applyEvent,
  removeApproval,
  createUserMessage,
  fromModelMessages,
  emptyUsage
} from './agentMessages'
import { DEFAULT_PRESET } from '@/components/ai-agent/presets'

export function useAgentSession(config = {}) {
  const scope = config.scope === 'terminal' ? 'terminal' : 'ops'
  const terminalHostId = config.hostId || ''
  const socket = ref(null)
  const connected = ref(false)
  const connectError = ref('')

  const state = reactive({
    sessionId: '',
    title: '',
    messages: [],
    pendingApprovals: [],
    // usage 是会话累计量（以库里为准），turnUsage 是本轮实时累加
    usage: emptyUsage(),
    turnUsage: emptyUsage(),
    running: false,
    aborted: false,
    error: null,
    finishReason: '',
    policy: null,
    clamped: null,
    availableTools: [],
    waitingForModel: false,
    stopping: false,
    completionId: 0,
    terminalCancelWarning: '',
    plusRequired: null
  })

  const options = reactive({
    models: [],
    presets: [],
    defaultModel: '',
    defaultPreset: DEFAULT_PRESET,
    tools: [],
    plusAvailable: false
  })

  const savedTerminalPermission = localStorage.getItem('terminalAgentMode')

  const settings = reactive({
    modelId: localStorage.getItem(scope === 'terminal' ? 'terminalAgentModel' : 'agentModel') || '',
    preset: localStorage.getItem('agentMode') || DEFAULT_PRESET,
    hostIds: scope === 'terminal' && terminalHostId ? [terminalHostId,] : [],
    terminalPermission: ['review', 'assist', 'authorized',].includes(savedTerminalPermission)
      ? savedTerminalPermission
      : DEFAULT_PRESET
  })

  const sessions = ref([])
  const historyNotice = ref('')
  const cancelledTerminalRequests = new Set()
  const activeTerminalRequests = new Set()
  const pendingTerminalCancellations = new Set()
  let deferredTerminalEndEvent = null
  let plusRequiredTimer = null
  let plusRequiredDeadline = 0
  let plusRequiredRemainingMs = 0

  const canSend = computed(() => connected.value && !state.running && !state.stopping)

  function dismissPlusRequired() {
    if (plusRequiredTimer) {
      clearTimeout(plusRequiredTimer)
      plusRequiredTimer = null
    }
    plusRequiredDeadline = 0
    plusRequiredRemainingMs = 0
    state.plusRequired = null
  }

  function resumePlusRequiredTimer() {
    if (!state.plusRequired || plusRequiredTimer) return
    if (plusRequiredRemainingMs <= 0) return dismissPlusRequired()
    plusRequiredDeadline = Date.now() + plusRequiredRemainingMs
    plusRequiredTimer = setTimeout(dismissPlusRequired, plusRequiredRemainingMs)
  }

  function pausePlusRequiredTimer() {
    if (!state.plusRequired || !plusRequiredTimer) return
    plusRequiredRemainingMs = Math.max(0, plusRequiredDeadline - Date.now())
    clearTimeout(plusRequiredTimer)
    plusRequiredTimer = null
  }

  function showPlusRequired(event) {
    dismissPlusRequired()
    state.plusRequired = {
      tool: event.tool,
      effect: event.effect,
      message: event.message || '非读取操作需激活 [Plus] 使用(解锁完整AI能力)',
      activationPath: event.activationPath || '/setting?tabKey=plus'
    }
    plusRequiredRemainingMs = 10 * 1000
    resumePlusRequiredTimer()
  }

  function resetConversation() {
    state.sessionId = ''
    state.title = ''
    state.messages.splice(0)
    state.pendingApprovals.splice(0)
    state.usage = emptyUsage()
    state.turnUsage = emptyUsage()
    state.running = false
    state.waitingForModel = false
    state.aborted = false
    state.error = null
    state.finishReason = ''
    state.stopping = false
    state.terminalCancelWarning = ''
    dismissPlusRequired()
    deferredTerminalEndEvent = null
    historyNotice.value = ''
  }

  function handleEvent(event) {
    switch (event.type) {
      case 'ready':
        options.models = event.models || []
        options.presets = event.presets || []
        options.defaultModel = event.defaultModel || ''
        options.defaultPreset = event.defaultPreset || DEFAULT_PRESET
        options.tools = Array.isArray(event.tools) ? event.tools : []
        options.plusAvailable = Boolean(event.plusAvailable)
        if (!settings.modelId || !options.models.includes(settings.modelId)) {
          settings.modelId = options.defaultModel
        }
        return

      case 'session_created':
        state.sessionId = event.session.id
        state.title = event.session.title
        return

      case 'session_saved':
        state.title = event.session.title
        // 库里的累计量是权威值，本轮增量已并入其中，就地清零避免重复计
        if (event.session.usage) {
          state.usage = { ...emptyUsage(), ...event.session.usage }
          state.turnUsage = emptyUsage()
        }
        refreshSessions()
        return

      case 'history_repaired':
        historyNotice.value = `已修复 ${ event.count } 处中断遗留的工具调用记录`
        return

      case 'compacted':
        // 压缩会丢掉原始细节，必须让用户知道，否则会疑惑"它怎么忘了前面说的"
        historyNotice.value = event.degraded
          ? `上下文超出预算，已裁剪最早的 ${ event.droppedCount } 条对话（摘要生成失败，细节已丢失）`
          : `上下文已压缩：${ event.droppedCount } 条历史对话被浓缩为摘要`
        return

      case 'pending_approvals':
        // 重连后后端告知仍有挂起的审批，但缺少完整上下文，
        // 只提示用户，具体卡片等后端重发 approval_request
        if (event.items?.length) {
          historyNotice.value = `有 ${ event.items.length } 个操作仍在等待确认`
        }
        return

      case 'tool_requires_plus':
        options.plusAvailable = false
        showPlusRequired(event)
        return

      case 'terminal_command_request':
        handleTerminalCommand(event)
        return

      case 'terminal_command_cancel':
        handleTerminalCommandCancel(event)
        return

      case 'stopped':
      case 'aborted':
        if (pendingTerminalCancellations.size) {
          deferredTerminalEndEvent = event
          return
        }
        applyEvent(state, event)
        return

      default:
        applyEvent(state, event)
    }
  }

  function connect() {
    if (socket.value) return
    const instance = generateSocketInstance('/ai-agent')
    socket.value = instance

    instance.on('connect', () => {
      connected.value = true
      connectError.value = ''
    })
    instance.on('connect_error', (error) => {
      connected.value = false
      connectError.value = error.message === 'No Cookie' ? '登录状态已失效，请重新登录' : error.message
    })
    instance.on('disconnect', () => {
      connected.value = false
      // 后端在 socket 断开时会中止本轮并清掉挂起的审批，前端必须同步收尾：
      // 只把 running 置 false 的话，进行中和等待确认的卡片会永远转圈
      const disconnectEvent = { type: 'error', message: '与服务端的连接已断开，本次任务已中止' }
      if (activeTerminalRequests.size) {
        deferredTerminalEndEvent = disconnectEvent
        cancelActiveTerminalRequests('Agent 连接已断开，正在中断远端命令')
      } else if (state.running || state.pendingApprovals.length) {
        applyEvent(state, disconnectEvent)
      }
      state.pendingApprovals.splice(0)
    })
    instance.on('agent_event', handleEvent)
  }

  function disconnect() {
    if (!socket.value) return
    cancelActiveTerminalRequests('Agent 面板已关闭，正在中断远端命令')
    socket.value.off('agent_event', handleEvent)
    socket.value.close()
    socket.value = null
    connected.value = false
  }

  function send(text, extra = {}) {
    const content = String(text || '').trim()
    if (!content || !canSend.value) return

    state.messages.push(createUserMessage(content))
    state.aborted = false
    state.error = null
    state.terminalCancelWarning = ''
    state.running = true

    socket.value.emit('ws_agent_run', {
      sessionId: state.sessionId || undefined,
      input: content,
      modelId: settings.modelId,
      permission: settings.preset,
      hostIds: scope === 'terminal' ? [terminalHostId,] : settings.hostIds,
      scope,
      hostId: scope === 'terminal' ? terminalHostId : undefined,
      terminalPermission: scope === 'terminal' ? settings.terminalPermission : undefined,
      terminalContext: scope === 'terminal' ? extra.terminalContext : undefined
    })
  }

  async function handleTerminalCommand(event) {
    if (!socket.value || scope !== 'terminal') return
    activeTerminalRequests.add(event.requestId)
    let result = { ok: false, error: '当前不在终端 AI 会话中' }
    try {
      result = await config.onTerminalCommand?.({
        ...event,
        reportProgress: (progress = {}) => {
          socket.value?.emit('ws_terminal_command_progress', {
            requestId: event.requestId,
            output: progress.output,
            capturedAt: progress.capturedAt,
            durationMs: progress.durationMs
          })
        }
      }) || { ok: false, error: '终端命令处理器不可用' }
    } catch (error) {
      result = { ok: false, error: error.message || '写入终端失败' }
    } finally {
      activeTerminalRequests.delete(event.requestId)
    }
    // 已取消的请求不再回写 agent socket；服务端已结束该等待，回写只会
    // 产生“请求已失效”的噪声。
    if (cancelledTerminalRequests.delete(event.requestId)) {
      if (result.ok && !pendingTerminalCancellations.has(event.requestId)) {
        state.terminalCancelWarning = ''
      }
      return
    }
    socket.value?.emit('ws_terminal_command_result', {
      requestId: event.requestId,
      ok: Boolean(result.ok),
      error: result.error,
      output: result.output,
      capturedAt: result.capturedAt,
      durationMs: result.durationMs,
      exitCode: result.exitCode
    })
  }

  async function handleTerminalCommandCancel(event) {
    if (scope !== 'terminal' || !event.requestId) return
    if (pendingTerminalCancellations.has(event.requestId)) return
    cancelledTerminalRequests.add(event.requestId)
    pendingTerminalCancellations.add(event.requestId)
    state.stopping = true
    state.terminalCancelWarning = ''
    let result
    try {
      result = await config.onTerminalCommandCancel?.(event)
    } catch (error) {
      result = { ok: false, error: error.message || '发送中断请求失败' }
    } finally {
      pendingTerminalCancellations.delete(event.requestId)
      state.stopping = pendingTerminalCancellations.size > 0
    }

    if (!result?.ok) {
      state.terminalCancelWarning = result?.error || '无法确认远端命令已停止，请在终端中人工核对'
    }

    if (!pendingTerminalCancellations.size && deferredTerminalEndEvent) {
      const finalEvent = deferredTerminalEndEvent
      deferredTerminalEndEvent = null
      applyEvent(state, finalEvent)
    }
  }

  function cancelActiveTerminalRequests(reason) {
    for (const requestId of activeTerminalRequests) {
      handleTerminalCommandCancel({ requestId, reason })
    }
  }

  function stop() {
    if (!socket.value) return
    cancelActiveTerminalRequests('用户已停止对话，正在中断远端命令')
    socket.value.emit('ws_agent_stop')
  }

  function respondApproval(requestId, approved, scope = 'once') {
    if (!socket.value) return
    socket.value.emit('ws_agent_approve', { requestId, approved, scope })
    removeApproval(state, requestId)
  }

  async function refreshSessions() {
    try {
      const params = scope === 'terminal'
        ? { scope: 'terminal', hostId: terminalHostId }
        : { scope: 'ops' }
      const { data } = await $api.getAgentSessions(params)
      sessions.value = data || []
    } catch {
      // 列表拉取失败不该打断对话，静默处理
    }
  }

  async function loadSession(id) {
    if (state.running) return
    const { data } = await $api.getAgentSessionDetail(id)
    applySession(data)
  }

  function applySession(data) {
    if ((data.scope || 'ops') !== scope || (scope === 'terminal' && data.hostId !== terminalHostId)) {
      throw new Error('该会话不属于当前 AI 助手')
    }
    resetConversation()
    state.sessionId = data.id
    state.title = data.title
    state.messages.push(...fromModelMessages(data.messages, data.toolMeta, data.turnMeta))
    state.usage = { ...emptyUsage(), ...(data.usage || {}) }
    if (data.modelId && options.models.includes(data.modelId)) settings.modelId = data.modelId
    if (data.permission) settings.preset = data.permission
    if (Array.isArray(data.hostIds)) settings.hostIds = [...data.hostIds,]
  }

  async function forkSession(turnIndex, messageIndex) {
    if (state.running) throw new Error('当前任务仍在执行')
    if (!state.sessionId) throw new Error('当前消息尚未保存，请稍后再试')
    const { data } = await $api.forkAgentSession(state.sessionId, { turnIndex, messageIndex })
    applySession(data)
    await refreshSessions()
    return data
  }

  async function removeSession(id) {
    await $api.removeAgentSession(id)
    if (state.sessionId === id) resetConversation()
    await refreshSessions()
  }

  async function clearSessions() {
    const params = scope === 'terminal'
      ? { scope: 'terminal', hostId: terminalHostId }
      : { scope: 'ops' }
    await $api.clearAgentSessions(params)
    resetConversation()
    await refreshSessions()
  }

  async function renameSession(id, title) {
    await $api.updateAgentSession(id, { title })
    await refreshSessions()
    if (state.sessionId === id) state.title = title
  }

  function setModel(modelId) {
    settings.modelId = modelId
    localStorage.setItem(scope === 'terminal' ? 'terminalAgentModel' : 'agentModel', modelId)
  }

  function setPreset(preset) {
    settings.preset = preset
    localStorage.setItem('agentMode', preset)
  }

  function setTerminalPermission(permission) {
    settings.terminalPermission = ['review', 'assist', 'authorized',].includes(permission) ? permission : DEFAULT_PRESET
    localStorage.setItem('terminalAgentMode', settings.terminalPermission)
  }

  onBeforeUnmount(() => {
    dismissPlusRequired()
    disconnect()
  })

  return {
    socket,
    connected,
    connectError,
    state,
    options,
    settings,
    sessions,
    historyNotice,
    canSend,
    connect,
    disconnect,
    send,
    stop,
    dismissPlusRequired,
    pausePlusRequiredTimer,
    resumePlusRequiredTimer,
    respondApproval,
    resetConversation,
    refreshSessions,
    loadSession,
    forkSession,
    removeSession,
    clearSessions,
    renameSession,
    setModel,
    setPreset,
    setTerminalPermission
  }
}
