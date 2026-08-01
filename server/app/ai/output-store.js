/**
 * 工具输出暂存
 *
 * exec 的输出很容易吃满上下文（一个 `journalctl` 就是几万行）。
 * 策略：超过阈值的输出只把首尾片段喂给模型，完整内容留在这里，
 * 同时给模型一个 handle，需要细看时用 read_output 按需回读。
 *
 * 直接丢弃超长部分会让模型"看不到却以为看到了"，比截断更危险。
 */

import { randomUUID } from 'node:crypto'
import { redact } from './redact.js'

// 单条输出直接进上下文的上限
const INLINE_LIMIT = 8 * 1024
// 截断时首尾各保留多少
const HEAD_KEEP = 5 * 1024
const TAIL_KEEP = 2 * 1024
// 暂存保留时长与条数上限
const TTL_MS = 30 * 60 * 1000
const MAX_ENTRIES = 200

/** handle -> { content, createdAt, meta } */
const store = new Map()

function evict() {
  const now = Date.now()
  for (const [handle, entry] of store.entries()) {
    if (now - entry.createdAt > TTL_MS) store.delete(handle)
  }
  while (store.size > MAX_ENTRIES) {
    const oldest = store.keys().next().value
    store.delete(oldest)
  }
}

/**
 * 把一段输出装配成适合喂给模型的文本。
 *
 * @param {string} content
 * @param {object} [meta] 附加信息（hostId、命令等），便于排查
 * @returns {{ text: string, handle: string|null, truncated: boolean, totalBytes: number }}
 */
export function fit(content, meta = {}, options = {}) {
  const raw = typeof content === 'string' ? content : String(content ?? '')
  const { text, redacted } = options.allowSensitive
    ? { text: raw, redacted: false }
    : redact(raw)
  const totalBytes = Buffer.byteLength(text)

  if (totalBytes <= INLINE_LIMIT) {
    return { text, handle: null, truncated: false, totalBytes, redacted }
  }

  evict()
  const handle = randomUUID()
  store.set(handle, { content: text, createdAt: Date.now(), meta })

  const head = text.slice(0, HEAD_KEEP)
  const tail = text.slice(-TAIL_KEEP)
  const omitted = totalBytes - Buffer.byteLength(head) - Buffer.byteLength(tail)

  const notice = `\n\n... [已省略约 ${ omitted } 字节，共 ${ totalBytes } 字节。`
    + `需要查看完整内容时用 read_output 工具，handle: ${ handle }] ...\n\n`

  return { text: head + notice + tail, handle, truncated: true, totalBytes, redacted }
}

/**
 * 按 handle 回读暂存内容
 * @param {string} handle
 * @param {object} [options]
 * @param {number} [options.offset] 起始字符位置
 * @param {number} [options.limit] 读取长度
 * @param {string} [options.pattern] 只返回匹配该正则的行
 */
export function read(handle, options = {}) {
  const entry = store.get(handle)
  if (!entry) {
    return { ok: false, error: '该输出已过期或不存在，请重新执行命令获取' }
  }
  if (!options.sessionId || entry.meta?.sessionId !== options.sessionId) {
    return { ok: false, error: '该输出不属于当前会话，请重新执行命令获取' }
  }

  const { content } = entry

  if (options.pattern) {
    let regex
    try {
      regex = new RegExp(options.pattern, 'i')
    } catch {
      return { ok: false, error: `无效的正则表达式: ${ options.pattern }` }
    }
    const matched = content.split('\n').filter((line) => regex.test(line))
    const joined = matched.join('\n')
    return {
      ok: true,
      content: joined.slice(0, INLINE_LIMIT),
      matchedLines: matched.length,
      truncated: Buffer.byteLength(joined) > INLINE_LIMIT
    }
  }

  const offset = Math.max(0, options.offset || 0)
  const limit = Math.min(options.limit || INLINE_LIMIT, INLINE_LIMIT)
  const slice = content.slice(offset, offset + limit)

  return {
    ok: true,
    content: slice,
    offset,
    totalLength: content.length,
    hasMore: offset + slice.length < content.length
  }
}

/** 会话结束时清理其产生的暂存 */
export function clearBySession(sessionId) {
  for (const [handle, entry] of store.entries()) {
    if (entry.meta?.sessionId === sessionId) store.delete(handle)
  }
}

export function size() {
  return store.size
}
