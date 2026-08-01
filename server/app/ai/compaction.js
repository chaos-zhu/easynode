/**
 * 上下文压缩
 *
 * exec 的输出极易吃满上下文：一次 `journalctl` 或 `df -h` 就是几千 token，
 * 十几轮下来必然超限。session-store 的按轮次裁剪只是硬丢，会让 agent 忘掉
 * 前面已经查明的事实，反复重跑同样的命令。这里补上摘要压缩。
 *
 * 策略：
 *   保留最近 N 轮原文 + 把更早的部分压成一段摘要，摘要以 user/assistant
 *   问答对的形式回填。不用 system 消息，因为部分厂商只接受单条 system。
 *
 * 两个触发点：
 *   1. 主动 —— 发请求前估算超过阈值
 *   2. 被动 —— 厂商返回上下文超限错误后强制压缩重试一次
 *
 * token 估算天然不准（不同厂商分词器不同），所以被动这条不能省。
 */

import { generateText } from 'ai'

// 默认上下文预算。第三方模型五花八门，取一个多数模型都扛得住的保守值，
// 用户可在 AI 配置里用 contextLimit 覆盖。
export const DEFAULT_CONTEXT_LIMIT = 64 * 1024
// 达到预算的这个比例就触发压缩，留出本轮输出的空间
const COMPACT_RATIO = 0.7
// 保留原文的最近轮数
const KEEP_RECENT_TURNS = 3
// 摘要本身的长度上限
const SUMMARY_MAX_TOKENS = 800
// 单条工具输出进入摘要素材时的截断长度
const TRANSCRIPT_TOOL_LIMIT = 800

/**
 * 粗略估算 token 数。
 *
 * 中英文密度差别很大：英文约 4 字符/token，中文约 1.5 字符/token。
 * 只按字符数除以固定值会在中文场景严重低估，反而更容易撞上限。
 */
export function estimateTokens(input) {
  if (input === null || input === undefined) return 0
  const text = typeof input === 'string' ? input : JSON.stringify(input)
  if (!text) return 0

  let cjk = 0
  for (const char of text) {
    const code = char.codePointAt(0)
    // CJK 统一表意文字 + 日文假名 + 全角标点
    if ((code >= 0x4e00 && code <= 0x9fff)
      || (code >= 0x3040 && code <= 0x30ff)
      || (code >= 0xff00 && code <= 0xffef)
      || (code >= 0x3000 && code <= 0x303f)) {
      cjk += 1
    }
  }
  const other = text.length - cjk
  return Math.ceil(cjk / 1.5 + other / 4)
}

export function estimateMessagesTokens(messages = []) {
  // 每条消息有固定开销（role、分隔符），按 4 token 计
  return messages.reduce((total, message) => total + estimateTokens(message) + 4, 0)
}

function toArray(content) {
  if (Array.isArray(content)) return content
  if (content === null || content === undefined) return []
  return [{ type: 'text', text: String(content) }]
}

function truncate(text, limit) {
  const value = typeof text === 'string' ? text : JSON.stringify(text ?? '')
  if (value.length <= limit) return value
  return `${ value.slice(0, limit) }…（已截断，原长 ${ value.length } 字符）`
}

/**
 * 把消息渲染成纯文本笔录，作为摘要素材。
 *
 * 不直接把 ModelMessage[] 丢给 generateText，因为那样必须保证 tool-call
 * 与 tool-result 严格配对，而待压缩的这一段恰恰可能被截断过。渲染成文本
 * 就绕开了这个约束，也更好控制素材长度。
 */
export function renderTranscript(messages = []) {
  const lines = []

  for (const message of messages) {
    if (message.role === 'user') {
      lines.push(`【用户】${ truncate(toArray(message.content).map((part) => part.text || '').join(''), 1000) }`)
      continue
    }

    if (message.role === 'assistant') {
      for (const part of toArray(message.content)) {
        if (part.type === 'text' && part.text?.trim()) {
          lines.push(`【助手】${ truncate(part.text, 1000) }`)
        } else if (part.type === 'tool-call') {
          lines.push(`【调用】${ part.toolName } ${ truncate(part.input, 300) }`)
        }
      }
      continue
    }

    if (message.role === 'tool') {
      for (const part of toArray(message.content)) {
        if (part.type !== 'tool-result') continue
        const value = part.output?.value ?? part.output
        const isError = String(part.output?.type || '').startsWith('error')
        lines.push(`【结果${ isError ? '·失败' : '' }】${ truncate(value, TRANSCRIPT_TOOL_LIMIT) }`)
      }
    }
  }

  return lines.join('\n')
}

const SUMMARY_PROMPT = `你在为一个 Linux 服务器运维助手压缩对话历史。请把下面的笔录浓缩成一段结构化摘要，供助手继续工作时参考。

必须保留：
1. **已执行的操作** —— 在哪台主机上做了什么，结果成功还是失败
2. **已查明的事实** —— 具体的数值、路径、版本、配置项、错误信息，原样保留不要概括成"某些配置"
3. **未完成的事项** —— 计划了但还没做的步骤
4. **用户的要求与偏好** —— 明确提出的约束、否决过的方案

要求：
- 用中文，分条列出，不要客套话
- 宁可保留具体数据也不要为了简短而丢失细节，这些数据助手后面还要用
- 不要臆测笔录里没有的内容
- 只输出摘要正文`

/**
 * 找到安全的切分点：从 keepRecentTurns 轮之前的那条 user 消息处切。
 *
 * 必须切在 user 消息上，否则会把 assistant 的 tool-call 和它的 tool-result
 * 拆到两边，留下的部分就是残缺历史。
 *
 * @returns {number} 切分下标；-1 表示没有可切的点
 */
export function findSplitIndex(messages, keepRecentTurns = KEEP_RECENT_TURNS) {
  const userIndexes = []
  for (let i = 0; i < messages.length; i += 1) {
    if (messages[i].role === 'user') userIndexes.push(i)
  }
  // 轮数不够，没什么可压的
  if (userIndexes.length <= keepRecentTurns) return -1

  const splitAt = userIndexes[userIndexes.length - keepRecentTurns]
  // 切掉的部分太短，压缩收益抵不上一次模型调用
  return splitAt >= 2 ? splitAt : -1
}

/** 摘要回填成一问一答，兼容只允许单条 system 的厂商 */
export function buildSummaryMessages(summary, droppedCount) {
  return [
    {
      role: 'user',
      content: `[上下文摘要] 为节省上下文，此前 ${ droppedCount } 条对话已被压缩。以下是其中的关键信息，请在后续工作中继续参考：\n\n${ summary }`
    },
    {
      role: 'assistant',
      content: '已了解以上背景，我会基于这些信息继续。'
    }
  ]
}

/**
 * 压缩消息历史。
 *
 * @param {object} params
 * @param {Array}  params.messages
 * @param {object} [params.model] AI SDK 模型实例，用于生成摘要
 * @param {number} [params.contextLimit]
 * @param {number} [params.keepRecentTurns]
 * @param {boolean} [params.force] 忽略阈值强制压缩（用于超限重试）
 * @param {AbortSignal} [params.signal]
 * @param {(transcript: string) => Promise<string>} [params.summarize] 注入摘要实现，便于测试
 * @returns {Promise<{ messages, compacted, summary, droppedCount, beforeTokens, afterTokens, reason }>}
 */
export async function compactMessages(params) {
  const {
    messages = [],
    model,
    contextLimit = DEFAULT_CONTEXT_LIMIT,
    keepRecentTurns = KEEP_RECENT_TURNS,
    force = false,
    signal
  } = params

  const beforeTokens = estimateMessagesTokens(messages)
  const threshold = Math.floor(contextLimit * COMPACT_RATIO)

  const unchanged = (reason) => ({
    messages,
    compacted: false,
    summary: '',
    droppedCount: 0,
    splitAt: -1,
    beforeTokens,
    afterTokens: beforeTokens,
    reason
  })

  if (!force && beforeTokens < threshold) return unchanged('under-threshold')

  const splitAt = findSplitIndex(messages, keepRecentTurns)
  // 强制压缩时退一步，只保留最后一轮，尽可能腾出空间
  const effectiveSplit = splitAt === -1 && force ? findSplitIndex(messages, 1) : splitAt
  if (effectiveSplit === -1) return unchanged('nothing-to-compact')

  const older = messages.slice(0, effectiveSplit)
  const recent = messages.slice(effectiveSplit)

  // 连续压缩时要把上一次的摘要一并喂进去，否则更早的信息会在第二次
  // 压缩时彻底丢失
  const transcript = [
    params.previousSummary ? `【此前的摘要】\n${ params.previousSummary }` : '',
    renderTranscript(older)
  ].filter(Boolean).join('\n\n')

  if (!transcript.trim()) return unchanged('empty-transcript')

  const summarize = params.summarize || (async (text) => {
    if (!model) throw new Error('缺少用于生成摘要的模型')
    const result = await generateText({
      model,
      system: SUMMARY_PROMPT,
      prompt: text,
      maxOutputTokens: SUMMARY_MAX_TOKENS,
      abortSignal: signal
    })
    return result.text
  })

  let summary
  try {
    summary = (await summarize(transcript)).trim()
  } catch (error) {
    // 摘要失败不能让整个 turn 挂掉。降级为直接丢弃旧消息 ——
    // 丢了上下文总比整个请求失败强，但要让用户知道发生了什么。
    logger.warn(`[ai-compaction] 生成摘要失败，降级为直接裁剪: ${ error.message }`)
    const fallback = [...recent]
    return {
      messages: fallback,
      compacted: true,
      degraded: true,
      summary: '',
      droppedCount: older.length,
      splitAt: effectiveSplit,
      beforeTokens,
      afterTokens: estimateMessagesTokens(fallback),
      reason: `summary-failed: ${ error.message }`
    }
  }

  if (!summary) return unchanged('empty-summary')

  const compactedMessages = [...buildSummaryMessages(summary, older.length), ...recent]

  return {
    messages: compactedMessages,
    compacted: true,
    summary,
    droppedCount: older.length,
    splitAt: effectiveSplit,
    beforeTokens,
    afterTokens: estimateMessagesTokens(compactedMessages),
    reason: force ? 'forced' : 'over-threshold'
  }
}

/** 判断一个错误是不是上下文超限，用于决定要不要强制压缩重试 */
export function isContextLengthError(error) {
  const message = String(error?.message || error || '').toLowerCase()
  const status = error?.statusCode || error?.status
  if (status === 413) return true
  return [
    'context length',
    'context_length_exceeded',
    'maximum context',
    'too many tokens',
    'reduce the length',
    'request too large',
    'prompt is too long',
    'input length and `max_tokens` exceed'
  ].some((keyword) => message.includes(keyword))
}
