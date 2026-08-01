/**
 * Agent 消息模型
 *
 * 这里只放纯函数：把 socket 事件流和后端存的 ModelMessage[] 都收敛成同一套
 * 渲染结构。两条来路（实时流式 / 刷新后还原）必须产出完全一致的形状，
 * 否则同一段对话在刷新前后会长得不一样。
 *
 * 消息结构：
 *   { id, role, parts: Part[], createdAt }
 *
 * Part：
 *   { type: 'text',      text }
 *   { type: 'reasoning', text, done }
 *   { type: 'tool',      toolCallId, tool, input, status, output, error, durationMs, risk, approval }
 */

export const ToolStatus = {
  RUNNING: 'running',
  AWAITING_APPROVAL: 'awaiting-approval',
  DONE: 'done',
  ERROR: 'error',
  DENIED: 'denied'
}

let seq = 0
const nextId = (prefix) => `${ prefix }-${ Date.now().toString(36) }-${ (seq += 1).toString(36) }`

export function createUserMessage(text) {
  return {
    id: nextId('u'),
    role: 'user',
    parts: [{ type: 'text', text },],
    createdAt: Date.now()
  }
}

export function createAssistantMessage() {
  return {
    id: nextId('a'),
    role: 'assistant',
    parts: [],
    createdAt: Date.now()
  }
}

function lastPart(message) {
  return message.parts[message.parts.length - 1]
}

/** 追加流式文本：连续的同类增量并进同一个 part，避免渲染出一堆碎片 */
function appendStreamText(message, type, text) {
  const tail = lastPart(message)
  if (tail?.type === type && !tail.done) {
    tail.text += text
    return
  }
  message.parts.push({ type, text })
}

function findToolPart(messages, toolCallId) {
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const part = messages[i].parts?.find((item) => item.type === 'tool' && item.toolCallId === toolCallId)
    if (part) return part
  }
  return null
}

/** 思考流结束后就该定型，后续的正文不能再并进去 */
function sealReasoning(message) {
  const tail = lastPart(message)
  if (tail?.type === 'reasoning') tail.done = true
}

/**
 * 把一个 socket 事件应用到消息列表上。
 *
 * @param {object} state { messages, usage, running, error, pendingApprovals }
 * @param {object} event
 * @returns {object} 需要外部感知的副作用，如 { sessionCreated }
 */
export function applyEvent(state, event) {
  const current = () => state.messages[state.messages.length - 1]

  switch (event.type) {
    case 'turn_start': {
      state.running = true
      state.waitingForModel = false
      state.error = null
      // 本轮用量单独计，与会话累计量分开。混在一起会导致第二轮开始时
      // finish 用本轮总量覆盖掉累计值，出现"数字先涨后跌再涨"的闪烁
      state.turnUsage = emptyUsage()
      state.policy = event.policy
      state.clamped = event.clamped
      state.availableTools = event.availableTools || []
      state.messages.push(createAssistantMessage())
      break
    }

    case 'text_delta': {
      state.waitingForModel = false
      const message = current()
      if (!message) break
      sealReasoning(message)
      appendStreamText(message, 'text', event.text)
      break
    }

    case 'reasoning_delta': {
      state.waitingForModel = false
      const message = current()
      if (!message) break
      appendStreamText(message, 'reasoning', event.text)
      break
    }

    case 'tool_call': {
      state.waitingForModel = false
      const message = current()
      if (!message) break
      sealReasoning(message)
      const pendingApproval = state.pendingApprovals.find((item) => item.toolCallId === event.toolCallId)
      const scriptName = event.tool === 'run_script' ? pendingApproval?.input?.scriptName : ''
      message.parts.push({
        type: 'tool',
        toolCallId: event.toolCallId,
        tool: event.tool,
        input: scriptName ? { ...event.input, scriptName } : event.input,
        status: ToolStatus.RUNNING
      })
      break
    }

    case 'tool_progress': {
      const part = findToolPart(state.messages, event.toolCallId)
      if (!part) break
      if (event.durationMs !== undefined) part.durationMs = event.durationMs
      break
    }

    case 'terminal_command_progress': {
      const part = findToolPart(state.messages, event.toolCallId)
      if (!part) break
      if (event.durationMs !== undefined) part.durationMs = event.durationMs
      if (event.output !== undefined) part.progressOutput = event.output
      part.progressAt = event.capturedAt || Date.now()
      break
    }

    case 'tool_result': {
      const part = findToolPart(state.messages, event.toolCallId)
      if (!part) break
      if (event.error) {
        part.status = ToolStatus.ERROR
        part.error = event.error
      } else {
        part.status = ToolStatus.DONE
        part.output = normalizeToolOutput(event.output)
      }
      break
    }

    case 'awaiting_model': {
      state.waitingForModel = true
      break
    }

    case 'model_resumed': {
      state.waitingForModel = false
      break
    }

    case 'tool_denied': {
      const part = findToolPart(state.messages, event.toolCallId)
      if (!part) break
      part.status = ToolStatus.DENIED
      part.error = event.reason
      part.risk = event.permanent
        ? { level: 'deny', reason: event.reason, category: event.category }
        : undefined
      break
    }

    case 'approval_request': {
      const part = findToolPart(state.messages, event.toolCallId)
      // 审批发生在工具执行之前，此时 tool_call 事件可能还没到
      if (part) {
        part.status = ToolStatus.AWAITING_APPROVAL
        part.risk = event.risk
        if (event.tool === 'run_script' && event.input?.scriptName) {
          part.input = { ...part.input, scriptName: event.input.scriptName }
        }
      }
      state.pendingApprovals.push({
        requestId: event.requestId,
        toolCallId: event.toolCallId,
        tool: event.tool,
        input: event.input,
        preview: event.preview,
        hostName: event.hostName,
        effect: event.effect,
        mode: event.mode,
        targets: event.targets,
        sensitiveDisclosure: event.sensitiveDisclosure,
        risk: event.risk,
        grantKey: event.grantKey,
        grantLabel: event.grantLabel,
        grantable: event.grantable,
        createdAt: Date.now()
      })
      break
    }

    case 'approval_timeout':
    case 'approval_cancelled': {
      removeApproval(state, event.requestId)
      break
    }

    case 'step_finish': {
      if (event.usage) accumulateUsage(state.turnUsage, event.usage)
      break
    }

    case 'finish': {
      state.running = false
      state.waitingForModel = false
      state.finishReason = event.finishReason
      state.completionId = (state.completionId || 0) + 1
      // 用 totalUsage 校正本轮估算；会话累计量由 session_saved 从库里带回，
      // 那才是权威值
      if (event.usage) {
        state.turnUsage = pickUsage(event.usage)
        const message = current()
        if (message?.role === 'assistant') message.usage = pickUsage(event.usage)
      }
      break
    }

    case 'aborted': {
      state.running = false
      state.waitingForModel = false
      state.aborted = true
      markUnfinishedTools(state, '已被用户中断')
      break
    }

    // 整轮失败：收尾所有未完成的工具
    case 'error': {
      state.running = false
      state.waitingForModel = false
      state.error = event.message
      markUnfinishedTools(state, event.message)
      break
    }

    // 流内的局部错误：只提示，不结束本轮，也不动工具状态
    case 'stream_error': {
      state.streamWarning = event.message
      break
    }

    case 'stopped': {
      state.running = false
      state.waitingForModel = false
      state.pendingApprovals.splice(0)
      markUnfinishedTools(state, '已停止')
      break
    }

    default:
      break
  }

  return event
}

export function removeApproval(state, requestId) {
  const index = state.pendingApprovals.findIndex((item) => item.requestId === requestId)
  if (index !== -1) state.pendingApprovals.splice(index, 1)
}

/** 流被打断时，把还挂在 running / 待审批的工具卡片收尾，避免永远转圈 */
function markUnfinishedTools(state, reason) {
  for (const message of state.messages) {
    for (const part of message.parts || []) {
      if (part.type !== 'tool') continue
      if (part.status === ToolStatus.RUNNING || part.status === ToolStatus.AWAITING_APPROVAL) {
        part.status = ToolStatus.ERROR
        part.error = reason
      }
    }
  }
}

function pickUsage(usage = {}) {
  return {
    inputTokens: usage.inputTokens || 0,
    outputTokens: usage.outputTokens || 0,
    totalTokens: usage.totalTokens || 0,
    cachedInputTokens: usage.cachedInputTokens || 0,
    reasoningTokens: usage.reasoningTokens || 0
  }
}

function accumulateUsage(target, usage) {
  const picked = pickUsage(usage)
  target.inputTokens += picked.inputTokens
  target.outputTokens += picked.outputTokens
  target.totalTokens += picked.totalTokens
  target.cachedInputTokens += picked.cachedInputTokens
  target.reasoningTokens += picked.reasoningTokens
}

export function emptyUsage() {
  return { inputTokens: 0, outputTokens: 0, totalTokens: 0, cachedInputTokens: 0, reasoningTokens: 0 }
}

export function messageText(message) {
  return (message?.parts || []).map((part) => part.text || '').join('').trim()
}

export function findPreviousUserMessage(messages = [], targetId) {
  const targetIndex = messages.findIndex((message) => message.id === targetId)
  for (let index = targetIndex - 1; index >= 0; index -= 1) {
    if (messages[index].role === 'user') return messages[index]
  }
  return null
}

export function findUserTurnIndex(messages = [], targetId) {
  const targetIndex = messages.findIndex((message) => message.id === targetId)
  if (targetIndex === -1) return -1

  let turnIndex = -1
  for (let index = 0; index <= targetIndex; index += 1) {
    if (messages[index].role === 'user') turnIndex += 1
  }
  return turnIndex
}

/**
 * AI SDK 的工具输出是 { type, value } 包装，渲染层只关心 value。
 * 错误类输出单独标记，卡片要按失败样式展示。
 */
export function normalizeToolOutput(output) {
  if (output === null || output === undefined) return null
  if (typeof output !== 'object' || Array.isArray(output)) return output
  if (typeof output.type === 'string' && 'value' in output) {
    return output.type.startsWith('error') ? { __error: true, value: output.value } : output.value
  }
  return output
}

// ------------------------------------------------- 从持久化历史还原

function contentParts(content) {
  if (Array.isArray(content)) return content
  if (content === null || content === undefined) return []
  return [{ type: 'text', text: String(content) },]
}

function joinText(content) {
  return contentParts(content)
    .filter((part) => part.type === 'text')
    .map((part) => part.text)
    .join('')
}

/**
 * ModelMessage[] + toolMeta → 渲染用的消息列表
 *
 * 后端存的是发给模型的规范格式，展示所需的风险判定、审批结果、耗时另存在
 * toolMeta 里，这里按 toolCallId 合回去。
 */
export function fromModelMessages(modelMessages = [], toolMeta = {}, turnMeta = []) {
  const messages = []
  const toolParts = new Map()
  let userTurnIndex = 0
  let activeTurnMeta = null
  let lastAssistantMessage = null

  const sealTurnUsage = () => {
    if (lastAssistantMessage && activeTurnMeta?.usage) {
      lastAssistantMessage.usage = pickUsage(activeTurnMeta.usage)
    }
    lastAssistantMessage = null
  }

  for (const [sourceIndex, raw,] of modelMessages.entries()) {
    if (!raw?.role) continue

    if (raw.role === 'user') {
      sealTurnUsage()
      activeTurnMeta = turnMeta[userTurnIndex] || null
      messages.push({
        id: nextId('u'),
        role: 'user',
        parts: [{ type: 'text', text: joinText(raw.content) },],
        createdAt: Number(turnMeta[userTurnIndex]?.createdAt) || 0
      })
      userTurnIndex += 1
      continue
    }

    if (raw.role === 'assistant') {
      const message = { id: nextId('a'), role: 'assistant', parts: [], createdAt: 0, sourceIndex }
      for (const part of contentParts(raw.content)) {
        if (part.type === 'text' && part.text) {
          message.parts.push({ type: 'text', text: part.text })
        } else if (part.type === 'reasoning' && part.text) {
          message.parts.push({ type: 'reasoning', text: part.text, done: true })
        } else if (part.type === 'tool-call') {
          const meta = toolMeta[part.toolCallId] || {}
          const toolPart = {
            type: 'tool',
            toolCallId: part.toolCallId,
            tool: part.toolName,
            input: part.toolName === 'run_script' && meta.scriptName
              ? { ...part.input, scriptName: meta.scriptName }
              : part.input,
            // 结果由后面的 tool 消息填，填不上说明历史残缺
            status: meta.denied ? ToolStatus.DENIED : ToolStatus.RUNNING,
            durationMs: meta.durationMs,
            risk: meta.risk && meta.risk !== 'normal'
              ? { level: meta.risk, reason: meta.riskReason, category: meta.riskCategory }
              : undefined,
            approval: meta.approved === undefined
              ? undefined
              : { approved: meta.approved, scope: meta.approvalScope, cached: meta.approvalCached }
          }
          message.parts.push(toolPart)
          toolParts.set(part.toolCallId, toolPart)
        }
      }
      if (message.parts.length) {
        messages.push(message)
        lastAssistantMessage = message
      }
      continue
    }

    if (raw.role === 'tool') {
      for (const part of contentParts(raw.content)) {
        if (part.type !== 'tool-result') continue
        const target = toolParts.get(part.toolCallId)
        if (!target) continue
        const normalized = normalizeToolOutput(part.output)
        if (normalized && typeof normalized === 'object' && normalized.__error) {
          target.status = target.status === ToolStatus.DENIED ? ToolStatus.DENIED : ToolStatus.ERROR
          target.error = String(normalized.value)
        } else {
          target.status = target.status === ToolStatus.DENIED ? ToolStatus.DENIED : ToolStatus.DONE
          target.output = normalized
        }
      }
    }
  }

  sealTurnUsage()

  // 历史里仍处于 running 的调用说明当时被打断了，还原成失败态而不是转圈
  for (const part of toolParts.values()) {
    if (part.status === ToolStatus.RUNNING) {
      part.status = ToolStatus.ERROR
      part.error = '该调用未完成，结果未知'
    }
  }

  return messages
}
