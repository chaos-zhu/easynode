import { apiPrefix, logConfig } from '../config/index.js'
import { getClientIP } from '../utils/tools.js'

const { DEBUG } = logConfig
const PRIVATE_KEY_DECRYPT_PATH = `${ apiPrefix }/decrypt-private-key`
const MASKED = '[MASKED]'

// ------------------ 脱敏 ------------------
// 可能包含敏感信息的 header key（小写比较）
const SENSITIVE_HEADER_KEYS = [
  'authorization', 'proxy-authorization', 'cookie', 'token', 'uid',
  'api-key', 'x-api-key'
]
// 需要打码的 body 字段（小写比较）
const SENSITIVE_BODY_KEYS = [
  'password', 'pwd', 'code', 'captcha', 'token',
  'oldloginname', 'oldpwd', 'newloginname', 'newpwd',
  'loginname', 'ciphertext', 'jwtexpires', 'mfa2token',
  'encryptedkey', 'privatekey', 'passphrase', 'secret', 'authorization',
  'tempkey', 'opensshkeypassword', 'apikey', 'session', 'qrimage'
]

const MAX_BODY_LOG_LEN = 1000 // 请求 body 最多记录长度
const MAX_RESULT_LOG_LEN = 1000 // 响应体最多记录长度

function maskSensitiveHeaders(headers = {}) {
  const safeHeaders = {}
  for (const [key, value] of Object.entries(headers)) {
    const lowerKey = key.toLowerCase()
    if (SENSITIVE_HEADER_KEYS.includes(lowerKey)) {
      safeHeaders[key] = MASKED
    } else {
      safeHeaders[key] = value
    }
  }
  return safeHeaders
}

function maskSensitiveBody(body) {
  if (!body || typeof body !== 'object') return body

  // 简单深拷贝 + 递归打码
  const clone = Array.isArray(body) ? [] : {}
  for (const [key, value] of Object.entries(body)) {
    const lowerKey = key.toLowerCase()

    if (SENSITIVE_BODY_KEYS.includes(lowerKey)) {
      clone[key] = MASKED
    } else if (value && typeof value === 'object') {
      clone[key] = maskSensitiveBody(value)
    } else {
      clone[key] = value
    }
  }

  return clone
}

function truncateString(str, maxLen) {
  if (typeof str !== 'string') return str
  if (!maxLen || str.length <= maxLen) return str
  return str.slice(0, maxLen) + '... [truncated]'
}

function safeStringify(obj, maxLen) {
  try {
    const json = JSON.stringify(obj)
    return truncateString(json, maxLen) // 避免循环引用
  } catch {
    return '[Unserializable object]'
  }
}

// 格式化请求 body，用于写入日志
function formatBodyForLog(body) {
  if (!body) return 'no body'

  // 文本请求体没有可用于脱敏的字段名。
  if (typeof body === 'string') {
    return `[text length=${ body.length }]`
  }

  // 其它类型（对象、数组等）先脱敏再 stringify
  const masked = maskSensitiveBody(body)
  return safeStringify(masked, MAX_BODY_LOG_LEN)
}

// 格式化响应 result，用于写入日志
function formatResultForLog(result) {
  if (result === null) return 'no content'

  // 字符串直接截断
  if (typeof result === 'string') {
    return truncateString(result, MAX_RESULT_LOG_LEN)
  }

  // Buffer
  if (Buffer.isBuffer(result)) {
    return `[buffer length=${ result.length }]`
  }

  // Stream（简单判断）
  if (result && typeof result.pipe === 'function') {
    return '[stream]'
  }

  // 其它对象，先脱敏再 stringify 截断
  const masked = result && typeof result === 'object' ? maskSensitiveBody(result) : result
  return safeStringify(masked, MAX_RESULT_LOG_LEN)
}

const useLog = async (ctx, next) => {
  if (!DEBUG) return next()

  const start = Date.now()
  await next()

  try {
    const { method, path, origin, query, body, headers } = ctx.request
    const { status } = ctx
    // 路由允许大小写变体和末尾斜杠，解密结果放在通用的 data 字段。
    const decryptsPrivateKey = path.toLowerCase().replace(/\/$/, '') === PRIVATE_KEY_DECRYPT_PATH
    const text = safeStringify({
      method,
      path,
      origin,
      ip: getClientIP(ctx.socket.remoteAddress, ctx.get('x-forwarded-for')),
      query: Object.fromEntries(Object.keys(query).map(key => [key, MASKED])),
      cost: Date.now() - start,
      headers: maskSensitiveHeaders(headers),
      body: decryptsPrivateKey ? MASKED : formatBodyForLog(body),
      status,
      params: ctx.params,
      result: decryptsPrivateKey || ctx.state.omitLogResult ? MASKED : formatResultForLog(ctx.body)
    })

    if (status >= 500) {
      logger.error(text)
    } else if (status >= 400) {
      logger.warn(text)
    } else {
      logger.info(text)
    }
  } catch (error) {
    logger.error('记录日志时发生错误', error)
  }
}

export default useLog
