// log4.js
const { DEBUG } = require('../config').logConfig

// ------------------ 脱敏 ------------------
// 可能包含敏感信息的 header key（小写比较）
const SENSITIVE_HEADER_KEYS = ['authorization', 'cookie', 'token', 'uid']
// 需要打码的 body 字段（小写比较）
const SENSITIVE_BODY_KEYS = [
  'password', 'pwd', 'code', 'captcha', 'token',
  'oldloginname', 'oldpwd', 'newloginname', 'newpwd',
  'loginname', 'ciphertext', 'jwtexpires', 'mfa2token'
]

const MAX_BODY_LOG_LEN = 1000 // 请求 body 最多记录长度
const MAX_RESULT_LOG_LEN = 1000 // 响应体最多记录长度

function maskSensitiveHeaders(headers = {}) {
  const safeHeaders = {}
  for (const [key, value] of Object.entries(headers)) {
    const lowerKey = key.toLowerCase()
    if (SENSITIVE_HEADER_KEYS.includes(lowerKey)) {
      safeHeaders[key] = '[MASKED]'
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
      clone[key] = '[MASKED]'
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
  } catch (e) {
    return '[Unserializable object]'
  }
}

// 格式化请求 body，用于写入日志
function formatBodyForLog(body) {
  if (!body) return 'no body'

  // 如果是字符串，直接截断
  if (typeof body === 'string') {
    return truncateString(body, MAX_BODY_LOG_LEN)
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

  // 其它对象，直接 stringify 截断
  return safeStringify(result, MAX_RESULT_LOG_LEN)
}

const useLog = () => {
  return async (ctx, next) => {
    const {
      method,
      path,
      origin,
      query,
      body,
      headers,
      ip
    } = ctx.request

    const start = Date.now()

    // 先让后续中间件 / 路由处理
    try {
      await next()
    } catch (err) {
      ctx._logError = err
      throw err
    } finally {
      // eslint-disable-next-line no-unsafe-finally
      if (!DEBUG) return

      const cost = Date.now() - start

      const logData = {
        method,
        path,
        origin,
        ip,
        query,
        cost, // 花费时间 ms
        headers: maskSensitiveHeaders(headers),
        body: formatBodyForLog(body),
        status: ctx.status,
        params: ctx.params,
        result: formatResultForLog(ctx.body)
      }

      // 如果有未捕获异常，可以顺带记一下
      if (ctx._logError) {
        logData.error = {
          message: ctx._logError.message,
          stack: ctx._logError.stack
        }
      }

      // 状态码分级：5xx error，4xx warn，其它 info
      const status = Number(ctx.status) || 0
      const text = safeStringify(logData)

      try {
        if (status >= 500) {
          logger.error(text)
        } else if (status >= 400) {
          logger.warn(text)
        } else {
          logger.info(text)
        }
      } catch (e) {
        logger.error('记录日志时发生错误', e)
      }
    }
  }
}

module.exports = useLog()
