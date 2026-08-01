/**
 * Agent 会话持久化
 *
 * 旧的 AI Chat 已下线，其 chat-history.db 保留在磁盘上未做迁移，
 * 但代码里不再引用。
 *
 * 存的是 ModelMessage[]（AI SDK 传给模型的规范格式）而不是渲染用的结构，
 * 因为续聊时必须原样回放给模型。渲染所需的额外信息（风险判定、审批结果、
 * 耗时）放在 toolMeta 里，按 toolCallId 关联。
 *
 * 最容易出事的地方是 tool-call 与 tool-result 的配对：turn 被中断、进程
 * 被杀、审批超时，都会留下"有 tool-call 没有 tool-result"的残缺历史。
 * 这种历史再发给模型，绝大多数厂商会直接返回 400。所以每次读出来都要
 * 先修复（见 repairMessages）。
 */

import { AgentSessionDB } from '../utils/db-class.js'
import { buildSummaryMessages, compactMessages } from './compaction.js'
import { DEFAULT_PRESET } from './policy.js'

const agentSessionDB = new AgentSessionDB().getInstance()

// 单个会话保留的消息条数与字节上限，超出后从最早的整轮开始丢弃
const MAX_MESSAGES = 200
const MAX_BYTES = 1.5 * 1024 * 1024
const TITLE_MAX_LENGTH = 30

// ------------------------------------------------------------ 消息完整性

function toArray(content) {
  if (Array.isArray(content)) return content
  if (content === undefined || content === null) return []
  return [{ type: 'text', text: String(content) }]
}

function collectToolCallIds(message) {
  return toArray(message.content)
    .filter((part) => part?.type === 'tool-call')
    .map((part) => ({ toolCallId: part.toolCallId, toolName: part.toolName }))
}

function collectToolResultIds(message) {
  return toArray(message.content)
    .filter((part) => part?.type === 'tool-result')
    .map((part) => part.toolCallId)
}

/**
 * 修复消息序列，保证可以安全地重新发给模型。
 *
 * 两类问题：
 *   1. assistant 发起了 tool-call，但没有对应的 tool-result
 *      —— 补一条合成结果说明被中断，而不是删掉 tool-call。
 *      删掉会让助手上一句"我来执行 X"变成无凭无据的空话，模型容易
 *      误以为已经执行成功过。
 *   2. tool-result 找不到对应的 tool-call —— 直接丢弃，这种消息非法。
 *
 * @param {Array} messages
 * @returns {{ messages: Array, repaired: number }}
 */
export function repairMessages(messages) {
  if (!Array.isArray(messages)) return { messages: [], repaired: 0 }

  const resolved = new Set()
  for (const message of messages) {
    if (message?.role !== 'tool') continue
    for (const id of collectToolResultIds(message)) resolved.add(id)
  }

  const output = []
  const seenCalls = new Set()
  let pendingOrphans = []
  let repaired = 0

  /**
   * 补偿消息要排在真实结果**之后**。虽然只要配对齐全大多数厂商都能接受，
   * 但保持"真实结果在前、补偿在后"的顺序更贴近正常时序，也不容易触发
   * 某些厂商对 tool 消息顺序的严格校验。
   */
  const flushOrphans = () => {
    if (!pendingOrphans.length) return
    repaired += pendingOrphans.length
    output.push({
      role: 'tool',
      content: pendingOrphans.map((call) => ({
        type: 'tool-result',
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        output: {
          type: 'error-text',
          value: '该工具调用因会话中断未能完成，结果未知。如仍需要，请重新执行并确认当前实际状态。'
        }
      }))
    })
    pendingOrphans = []
  }

  for (const message of messages) {
    if (!message?.role) continue

    if (message.role === 'tool') {
      const parts = toArray(message.content).filter((part) => {
        if (part?.type !== 'tool-result') return false
        // 结果必须出现在对应的调用之后
        return seenCalls.has(part.toolCallId)
      })
      if (parts.length) output.push({ ...message, content: parts })
      else repaired += 1
      continue
    }

    // 走到非 tool 消息说明上一轮工具结果已经收齐，此时补齐缺失的
    flushOrphans()

    if (message.role === 'assistant') {
      const calls = collectToolCallIds(message)
      calls.forEach((call) => seenCalls.add(call.toolCallId))
      output.push(message)
      pendingOrphans = calls.filter((call) => !resolved.has(call.toolCallId))
      continue
    }

    output.push(message)
  }

  flushOrphans()
  return { messages: output, repaired }
}

/**
 * 按轮次裁剪历史。
 *
 * 从最早开始丢，但必须丢到完整的一轮边界（下一条 user 消息）为止，
 * 否则会把 assistant / tool 的配对拦腰截断。
 */
export function truncateHistory(messages, { maxMessages = MAX_MESSAGES, maxBytes = MAX_BYTES } = {}) {
  let working = [...messages]
  let dropped = 0

  const overBudget = () => working.length > maxMessages
    || Buffer.byteLength(JSON.stringify(working)) > maxBytes

  while (overBudget() && working.length > 2) {
    // 丢掉开头这一轮：从第 0 条开始，直到下一条 user 消息之前
    let cut = 1
    while (cut < working.length && working[cut].role !== 'user') cut += 1
    if (cut >= working.length) break
    working = working.slice(cut)
    dropped += cut
  }

  return { messages: working, dropped }
}

// ---------------------------------------------------------------- CRUD

function deriveTitle(messages) {
  const first = messages.find((message) => message.role === 'user')
  if (!first) return '新会话'
  const text = typeof first.content === 'string'
    ? first.content
    : toArray(first.content).filter((part) => part.type === 'text').map((part) => part.text).join(' ')
  const cleaned = text.replace(/\s+/g, ' ').trim()
  if (!cleaned) return '新会话'
  return cleaned.length > TITLE_MAX_LENGTH ? `${ cleaned.slice(0, TITLE_MAX_LENGTH) }…` : cleaned
}

function deriveForkTitle(title, messages) {
  const suffix = '（Fork）'
  const source = String(title || deriveTitle(messages)).trim() || '新会话'
  const base = source.endsWith(suffix) ? source.slice(0, -suffix.length) : source
  const maxBaseLength = TITLE_MAX_LENGTH - suffix.length
  const shortened = base.length > maxBaseLength
    ? `${ base.slice(0, maxBaseLength - 1) }…`
    : base
  return `${ shortened }${ suffix }`
}

function normalizeTurnUsage(usage) {
  if (!usage || typeof usage !== 'object') return null
  return {
    inputTokens: Number(usage.inputTokens) || 0,
    outputTokens: Number(usage.outputTokens) || 0,
    totalTokens: Number(usage.totalTokens) || 0,
    cachedInputTokens: Number(usage.cachedInputTokens) || 0,
    reasoningTokens: Number(usage.reasoningTokens) || 0
  }
}

function normalize(record) {
  if (!record) return null
  const { _id, ...rest } = record
  return { id: _id, ...rest }
}

export async function createSession(input = {}) {
  const now = Date.now()
  const record = {
    title: input.title || '新会话',
    scope: input.scope === 'terminal' ? 'terminal' : 'ops',
    hostId: input.hostId || '',
    hostIds: Array.isArray(input.hostIds) ? input.hostIds : [],
    modelId: input.modelId || '',
    permission: input.permission || DEFAULT_PRESET,
    messages: [],
    // 与用户消息按轮次一一对应。时间与 Token 用量不塞进 ModelMessage，
    // 避免非标准字段进入模型 provider；旧会话没有该字段时按未知信息兼容。
    turnMeta: [],
    toolMeta: {},
    usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
    createdAt: now,
    updatedAt: now
  }
  const created = await agentSessionDB.insertAsync(record)
  return normalize(created)
}

export async function getSession(id) {
  if (!id) return null
  return normalize(await agentSessionDB.findOneAsync({ _id: id }))
}

/** 列表只返回摘要，不带 messages —— 历史可能有几百 KB */
export async function listSessions(filter = {}) {
  const query = {}
  // 旧会话创建时尚无 scope 字段，视为运维助手会话，不能因升级被历史列表隐藏。
  if (filter.scope === 'terminal') query.scope = 'terminal'
  if (filter.scope === 'ops') query.$or = [{ scope: 'ops' }, { scope: { $exists: false } }]
  if (filter.hostId) query.hostId = filter.hostId
  const records = await agentSessionDB.findAsync(query)
  return records
    .map((record) => ({
      id: record._id,
      title: record.title,
      scope: record.scope || 'ops',
      hostId: record.hostId || '',
      hostIds: record.hostIds || [],
      modelId: record.modelId,
      permission: record.permission,
      messageCount: (record.messages || []).length,
      usage: record.usage,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt
    }))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
}

export async function updateSession(id, patch = {}) {
  const allowed = ['title', 'hostIds', 'modelId', 'permission']
  const update = {}
  for (const key of allowed) {
    if (patch[key] !== undefined) update[key] = patch[key]
  }
  if (!Object.keys(update).length) return getSession(id)
  update.updatedAt = Date.now()
  await agentSessionDB.updateAsync({ _id: id }, { $set: update })
  return getSession(id)
}

/**
 * 从指定问答轮次创建独立分支。
 *
 * turnIndex 是用户消息序号。messageIndex 可进一步定位该轮中的某条
 * assistant 消息；它后面紧邻的 tool 结果也会保留，确保上下文合法。
 */
export async function forkSession(id, turnIndex, messageIndex) {
  const session = await getSession(id)
  if (!session) throw new Error('会话不存在')
  if (!Number.isInteger(turnIndex) || turnIndex < 0) throw new Error('消息序号无效')

  const messages = session.messages || []
  let currentTurn = -1
  let targetStart = -1
  let turnEnd = messages.length

  for (let index = 0; index < messages.length; index += 1) {
    if (messages[index].role !== 'user') continue
    currentTurn += 1
    if (currentTurn === turnIndex) targetStart = index
    if (currentTurn === turnIndex + 1) {
      turnEnd = index
      break
    }
  }

  if (targetStart === -1) throw new Error('要分支的消息不存在')

  let retainedEnd = turnEnd
  if (messageIndex !== undefined) {
    if (
      !Number.isInteger(messageIndex)
      || messageIndex < targetStart
      || messageIndex >= turnEnd
      || messages[messageIndex]?.role !== 'assistant'
    ) {
      throw new Error('要分支的回答不存在')
    }
    retainedEnd = messageIndex + 1
    while (retainedEnd < turnEnd && messages[retainedEnd]?.role === 'tool') retainedEnd += 1
  }

  const retainedMessages = messages.slice(0, retainedEnd)
  if (!retainedMessages.slice(targetStart).some((message) => message.role === 'assistant')) {
    throw new Error('目标回答尚未保存')
  }

  const retainedToolIds = new Set()
  for (const message of retainedMessages) {
    for (const call of collectToolCallIds(message)) retainedToolIds.add(call.toolCallId)
  }

  const retainedTurnMeta = (session.turnMeta || [])
    .slice(0, turnIndex + 1)
    .map((meta) => ({ ...meta, usage: meta?.usage ? { ...meta.usage } : undefined }))
  const usage = retainedTurnMeta.reduce((total, meta) => {
    const turnUsage = normalizeTurnUsage(meta?.usage)
    if (!turnUsage) return total
    for (const key of Object.keys(total)) total[key] += turnUsage[key]
    return total
  }, {
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    cachedInputTokens: 0,
    reasoningTokens: 0
  })
  // 分支包含完整原会话时，累计量仍以会话记录为准；这也兼容尚无
  // turnMeta.usage 的旧会话。缓存/推理量仅存在于逐轮元数据时继续保留求和值。
  if (retainedEnd === messages.length) {
    usage.inputTokens = Number(session.usage?.inputTokens) || usage.inputTokens
    usage.outputTokens = Number(session.usage?.outputTokens) || usage.outputTokens
    usage.totalTokens = Number(session.usage?.totalTokens) || usage.totalTokens
  }

  const now = Date.now()
  const record = {
    title: deriveForkTitle(session.title, retainedMessages),
    scope: session.scope === 'terminal' ? 'terminal' : 'ops',
    hostId: session.hostId || '',
    hostIds: [...(session.hostIds || [])],
    modelId: session.modelId || '',
    permission: session.permission || DEFAULT_PRESET,
    messages: retainedMessages.map((message) => structuredClone(message)),
    turnMeta: retainedTurnMeta,
    toolMeta: Object.fromEntries(
      Object.entries(session.toolMeta || {})
        .filter(([toolCallId]) => retainedToolIds.has(toolCallId))
        .map(([toolCallId, meta]) => [toolCallId, structuredClone(meta)])
    ),
    usage,
    createdAt: now,
    updatedAt: now
  }

  if (session.compaction?.summary && session.compaction.upTo <= retainedMessages.length) {
    record.compaction = structuredClone(session.compaction)
  }

  return normalize(await agentSessionDB.insertAsync(record))
}

export async function removeSession(id) {
  if (!id) return false
  const removed = await agentSessionDB.removeAsync({ _id: id })
  return removed > 0
}

/**
 * 按助手作用域清理历史。终端会话必须额外限定 hostId，避免一个终端页
 * 的清空操作误删其他已连接主机的对话。
 */
export async function removeSessions(filter = {}) {
  const query = {}
  if (filter.scope === 'terminal') {
    if (!filter.hostId) throw new Error('终端会话缺少主机标识')
    query.scope = 'terminal'
    query.hostId = filter.hostId
  } else if (filter.scope === 'ops') {
    // 兼容升级前未写入 scope 的运维助手历史。
    query.$or = [{ scope: 'ops' }, { scope: { $exists: false } }]
  } else {
    throw new Error('无效的会话范围')
  }
  return agentSessionDB.removeAsync(query, { multi: true })
}

/**
 * 用户编辑历史消息时，从该轮开始删除旧分支。
 *
 * 新内容不会在这里落盘，而是由随后的 appendTurn 与新的模型响应一起保存，
 * 这样不会让模型历史里出现两条相同的用户消息。turnIndex 用用户消息的序号
 * 而非底层数组下标，前端不需要了解 tool / assistant 消息如何穿插保存。
 */
export async function truncateForUserEdit(id, turnIndex, content) {
  const session = await getSession(id)
  if (!session) throw new Error('会话不存在')
  if (!Number.isInteger(turnIndex) || turnIndex < 0) throw new Error('消息序号无效')
  if (typeof content !== 'string' || !content.trim()) throw new Error('消息内容不能为空')

  let currentTurn = -1
  const targetIndex = (session.messages || []).findIndex((message) => {
    if (message.role === 'user') currentTurn += 1
    return currentTurn === turnIndex && message.role === 'user'
  })

  if (targetIndex === -1) throw new Error('要编辑的消息不存在')

  const retainedMessages = session.messages.slice(0, targetIndex)
  const retainedToolIds = new Set()
  for (const message of retainedMessages) {
    for (const call of collectToolCallIds(message)) retainedToolIds.add(call.toolCallId)
  }

  const toolMeta = Object.fromEntries(
    Object.entries(session.toolMeta || {}).filter(([toolCallId]) => retainedToolIds.has(toolCallId))
  )

  const update = {
    messages: retainedMessages,
    turnMeta: (session.turnMeta || []).slice(0, turnIndex),
    toolMeta,
    // 原摘要可能包含被编辑的旧消息，不能继续作为模型上下文。
    compaction: null,
    updatedAt: Date.now()
  }

  // 只有标题仍是系统根据首条消息自动生成的，才跟随首次提问的编辑更新；
  // 用户手动重命名过的会话标题应当保留。
  if (turnIndex === 0 && session.title === deriveTitle(session.messages)) {
    update.title = deriveTitle([...retainedMessages, { role: 'user', content: content.trim() }])
  }

  await agentSessionDB.updateAsync({ _id: id }, { $set: update })
  return getSession(id)
}

/**
 * 取出可直接发给模型的历史：套用已有摘要 + 修复配对 + 裁剪长度。
 *
 * 完整的 messages 始终保留（前端要拿它渲染历史），压缩结果以
 * `compaction: { summary, upTo }` 的形式单独存 —— upTo 之前的消息
 * 发给模型时替换成摘要。这样既不用每轮重新调模型生成摘要，
 * 用户也还能翻看原始对话。
 *
 * @returns {{ messages, repaired, dropped, compacted, session }}
 */
export async function loadForModel(id, options = {}) {
  const session = await getSession(id)
  if (!session) return { messages: [], repaired: 0, dropped: 0, compacted: false, session: null }

  const all = session.messages || []
  let compaction = session.compaction
  // 摘要本身始终是有效上下文；upTo 只表示"替换掉开头多少条"，
  // 被裁剪归零后摘要仍然要带上，否则模型会突然失忆
  let usable = Boolean(compaction?.summary)
  let covered = usable ? Math.min(Math.max(compaction.upTo || 0, 0), all.length) : 0
  let compactedNow = null

  // 主动压缩放在这里而不是 runtime，是因为只有在完整的会话消息数组上
  // 才能算出稳定的下标；runtime 拿到的已经是拼装过的视图，换算不回去
  if (options.model) {
    const result = await compactMessages({
      messages: all.slice(covered),
      model: options.model,
      contextLimit: options.contextLimit,
      previousSummary: usable ? compaction.summary : '',
      signal: options.signal
    })

    if (result.compacted && result.splitAt > 0) {
      // 摘要生成失败的降级路径没有摘要文本，不落库，避免把历史白丢
      if (result.summary) {
        const upTo = covered + result.splitAt
        await saveCompaction(id, { summary: result.summary, upTo })
        compaction = { summary: result.summary, upTo }
        usable = true
        covered = upTo
      }
      compactedNow = result
    }
  }

  // 先修复、裁剪未被摘要覆盖的部分，最后才把摘要拼到最前面。
  // 顺序反过来的话，裁剪会从头开始丢，第一个被丢掉的就是摘要本身 ——
  // 花了一次模型调用生成的东西白费，而且模型会突然失忆
  const repairedResult = repairMessages(all.slice(covered))
  const truncated = truncateHistory(repairedResult.messages)

  const messages = usable
    ? [...buildSummaryMessages(compaction.summary, covered), ...truncated.messages]
    : truncated.messages

  if (repairedResult.repaired) {
    logger.warn(`[ai-session] 会话 ${ id } 修复了 ${ repairedResult.repaired } 处残缺的工具调用`)
  }

  return {
    messages,
    repaired: repairedResult.repaired,
    dropped: truncated.dropped,
    compacted: Boolean(usable),
    // 仅本次新产生的压缩才需要通知前端，复用已有摘要时不该反复提示
    compactedNow,
    session
  }
}

/**
 * 记录一次压缩结果。
 *
 * upTo 是「被摘要覆盖到的消息条数」，相对于完整 messages 数组。
 * 后续追加的消息不受影响，下次压缩会把 upTo 往后推。
 */
export async function saveCompaction(id, { summary, upTo }) {
  if (!summary || !(upTo > 0)) return null
  await agentSessionDB.updateAsync(
    { _id: id },
    { $set: { compaction: { summary, upTo, createdAt: Date.now() }, updatedAt: Date.now() } }
  )
  return getSession(id)
}

/**
 * 追加一轮对话。
 *
 * @param {string} id
 * @param {object} payload
 * @param {Array}  payload.newMessages 本轮新增的 ModelMessage（用户输入 + 模型响应）
 * @param {number} [payload.createdAt] 本轮用户消息发送时间
 * @param {object} [payload.toolMeta] toolCallId -> 展示用的附加信息
 * @param {object} [payload.usage] 本轮 token 用量
 */
export async function appendTurn(id, payload = {}) {
  const session = await getSession(id)
  if (!session) throw new Error(`会话不存在: ${ id }`)

  const incoming = Array.isArray(payload.newMessages) ? payload.newMessages : []
  const merged = [...(session.messages || []), ...incoming]
  const existingUserCount = (session.messages || []).filter((message) => message.role === 'user').length
  const existingTurnMeta = Array.from(
    { length: existingUserCount },
    (_, index) => session.turnMeta?.[index] || { createdAt: 0 }
  )
  const incomingUserCount = incoming.filter((message) => message.role === 'user').length
  const incomingTurnMeta = Array.from(
    { length: incomingUserCount },
    (_, index) => {
      const meta = {
        createdAt: index === 0 && Number(payload.createdAt) > 0 ? Number(payload.createdAt) : Date.now()
      }
      if (index === 0 && payload.usage) meta.usage = normalizeTurnUsage(payload.usage)
      return meta
    }
  )

  /**
   * compaction.upTo 是 messages 数组的下标，而 repairMessages 会**插入**
   * 合成的 tool 消息、truncateHistory 会**从头丢弃** —— 两者都会让这个
   * 下标失效，指偏之后摘要就会覆盖错误的范围，甚至让真实消息永远发不到
   * 模型。所以：
   *   - 已被摘要覆盖的前缀原样保留，不参与修复（它本来就不会发给模型）
   *   - 裁剪只从前缀里丢，丢多少就把 upTo 减多少
   */
  const covered = Math.min(session.compaction?.upTo || 0, (session.messages || []).length)
  const prefix = merged.slice(0, covered)
  const { messages: repairedSuffix } = repairMessages(merged.slice(covered))

  const repaired = [...prefix, ...repairedSuffix]
  const { messages: bounded, dropped } = truncateHistory(repaired)
  const droppedUserCount = repaired
    .slice(0, dropped)
    .filter((message) => message.role === 'user')
    .length

  const update = {}
  if (session.compaction?.summary) {
    update.compaction = { ...session.compaction, upTo: Math.max(0, covered - dropped) }
  }

  const usage = {
    inputTokens: (session.usage?.inputTokens || 0) + (payload.usage?.inputTokens || 0),
    outputTokens: (session.usage?.outputTokens || 0) + (payload.usage?.outputTokens || 0),
    totalTokens: (session.usage?.totalTokens || 0) + (payload.usage?.totalTokens || 0)
  }

  Object.assign(update, {
    messages: bounded,
    turnMeta: [...existingTurnMeta, ...incomingTurnMeta].slice(droppedUserCount),
    toolMeta: { ...(session.toolMeta || {}), ...(payload.toolMeta || {}) },
    usage,
    updatedAt: Date.now()
  })

  // 首轮结束后用第一条用户消息生成标题
  if (session.title === '新会话') update.title = deriveTitle(bounded)

  await agentSessionDB.updateAsync({ _id: id }, { $set: update })
  return getSession(id)
}
