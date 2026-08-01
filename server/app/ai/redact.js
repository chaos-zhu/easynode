/**
 * 输出脱敏
 *
 * 工具输出会被发送到第三方模型服务，并可能落在对方的日志里。私钥、
 * token、密码一旦出去就等于泄露，且无法追回。这里在进入上下文之前
 * 做一次打码。
 *
 * 取舍：宁可少打码也不要毁掉正常输出 —— 把 df 的输出打成马赛克会让
 * agent 彻底没法工作。所以只匹配特征明确的内容。
 */

const PATTERNS = [
  // PEM 块（私钥、证书私钥）整体替换
  {
    regex: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
    replace: () => '[已移除私钥内容]'
  },
  // PuTTY 私钥
  {
    regex: /PuTTY-User-Key-File-\d[\s\S]*?Private-MAC:.*/g,
    replace: () => '[已移除私钥内容]'
  },
  // key=value / key: value 形式的敏感字段
  {
    regex: /\b([A-Za-z0-9_-]*(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|credential|private[_-]?key)[A-Za-z0-9_-]*)(\s*[:=]\s*)(['"]?)([^\s'"#,;]{4,})\3/gi,
    replace: (match, key, sep, quote) => `${ key }${ sep }${ quote }[已脱敏]${ quote }`
  },
  // JSON/YAML/shell 中带空格的引号值。单独一条规则避免上一条为了支持
  // 多行内容而变得过度贪婪。
  {
    regex: /\b([A-Za-z0-9_-]*(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|credential|private[_-]?key)[A-Za-z0-9_-]*)(\s*[:=]\s*)(['"])([^'"\r\n]{4,})\3/gi,
    replace: (match, key, sep, quote) => `${ key }${ sep }${ quote }[已脱敏]${ quote }`
  },
  // /etc/shadow / gshadow 的密码哈希字段
  {
    regex: /^([^:\r\n]+:)([^:\r\n]+)(:.*)$/gm,
    replace: (match, prefix, secret, suffix) => {
      if (!/^(?:!|\*|\$[0-9A-Za-z.-]+\$)/.test(secret)) return match
      return `${ prefix }[已脱敏]${ suffix }`
    }
  },
  // 常见服务商 token 前缀
  {
    regex: /\b(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b/g,
    replace: () => '[已脱敏]'
  },
  // Authorization 头
  {
    regex: /\b(Authorization\s*:\s*(?:Bearer|Basic)\s+)([A-Za-z0-9._~+/=-]{8,})/gi,
    replace: (match, prefix) => `${ prefix }[已脱敏]`
  },
  // 连接串里的密码：scheme://user:pass@host
  {
    regex: /\b([a-z][a-z0-9+.-]*:\/\/[^\s:/@]+:)([^\s@/]{2,})(@)/gi,
    replace: (match, prefix, secret, suffix) => `${ prefix }[已脱敏]${ suffix }`
  }
]

/**
 * @param {string} text
 * @returns {{ text: string, redacted: boolean }}
 */
export function redact(text) {
  if (typeof text !== 'string' || !text) return { text: text ?? '', redacted: false }

  let result = text
  let redacted = false

  for (const { regex, replace } of PATTERNS) {
    result = result.replace(regex, (...args) => {
      redacted = true
      return replace(...args)
    })
  }

  return { text: result, redacted }
}

/** 递归脱敏对象里的所有字符串字段 */
export function redactDeep(value) {
  let redacted = false

  const walk = (node) => {
    if (typeof node === 'string') {
      const result = redact(node)
      if (result.redacted) redacted = true
      return result.text
    }
    if (Array.isArray(node)) return node.map(walk)
    if (node && typeof node === 'object') {
      const output = {}
      for (const [key, item] of Object.entries(node)) output[key] = walk(item)
      return output
    }
    return node
  }

  const data = walk(value)
  return { data, redacted }
}
