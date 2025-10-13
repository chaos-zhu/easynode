/**
 * 终端高亮器和默认的规则定义
 */

// ANSI终端文字样式
export const TEXT_STYLES = {
  BOLD: '\x1b[1m', // 粗体/高亮
  ITALIC: '\x1b[3m', // 斜体
  UNDERLINE: '\x1b[4m', // 下划线
  RESET: '\x1b[0m' // 重置样式
}

// 默认颜色映射
export const DEFAULT_COLOR_MAPPING = {
  rule1: '#ff4d4f', // 错误
  rule2: '#fadb14', // 警告
  rule3: '#52c41a', // 成功
  rule4: '#13c2c2', // 信息
  rule5: '#eb2f96', // 网络
  rule6: '#1890ff', // 链接
  rule7: '#ffffff', // 日期时间
  rule8: '#8b5cf6' // 单位数据
}

// 按颜色分组的高亮规则
export const HIGHLIGHT_RULES = {
  // 规则1 - 错误类关键词
  rule1: {
    title: '错误类关键词',
    pattern: /\b(?:errors?|err|fail(?:ed|ure)?|fatal|critical|denied|refused|broken|crash(?:ed)?|exception|timeout|abort(?:ed)?|reject(?:ed)?|forbidden|unauthorized|conflict|corrupt(?:ed)?|missing|not found|unreachable|disconnect(?:ed)?|kill(?:ed)?|terminate(?:d)?|dead|died|panic|alarm|alert|emergency|severe|cannot|unable|impossible|blocked|locked|disaster|malformed|malicious|virus|breach|hack(?:ed)?|attack|exploit|vulnerability|damaged|destroyed|overload|overflow|outage|down|offline|inaccessible|unavailable|suspended|revoked|expired|expires|blacklisted|infected|compromised|hijacked|suspicious|illegal|loss|death|bad)\b/,
    flags: 'gi',
    fullLine: true,
    displayColor: DEFAULT_COLOR_MAPPING.rule1,
    backgroundColor: null,
    bold: true,
    italic: false,
    underline: false,
    enabled: true
  },

  // 规则2 - 警告类关键词
  rule2: {
    title: '警告类关键词',
    pattern: /\b(?:warn(?:ing)?s?|deprecated|caution|retry|retrying|retried|skipped|ignored|pause(?:d)?|delay(?:ed)?|slow|slower|outdated|obsolete|insecure|vulnerable|risky|unstable|experimental|beta|alpha|preview|temporary|temp|pending|throttle(?:d)?|restrict(?:ed)?|downgrade(?:d)?|fallback|backup|migration|maintenance|partial|limited|degraded|reduced|minor|notice|advisory|reminder|important|security|urgent|attention|required|mandatory|danger|risk|permission)\b/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule2,
    backgroundColor: null,
    bold: false,
    italic: true,
    underline: false,
    enabled: true
  },

  // 规则3 - 成功类关键词
  rule3: {
    title: '成功类关键词',
    pattern: /\b(?:success(?:ful)?|successfully|complete(?:d)?|completed|finish(?:ed)?|finished|ok(?:ay)?|ready|active|running|begin|launch(?:ed)?|launched|connect(?:ed)?|connected|online|available|enabled|valid|verified|confirmed|approved|passed|accepted|resolved|fixed|repaired|restored|recovered|upgraded|updated|installed|deployed|built|compiled|loaded|mounted|synchronized|synced|healthy|stable|secure|safe|protected|authenticated|authorized|granted|allowed|permitted|working|alive|opened|succeeded|established)\b/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule3,
    backgroundColor: null,
    bold: false,
    italic: false,
    underline: false,
    enabled: true
  },

  // 规则4 - 信息类关键词
  rule4: {
    title: '信息类关键词',
    pattern: /\b(?:info|information|notification|message|msg|debug|trace|verbose|status|report|summary|loading|connecting|processing|monitoring|checking|scanning|analyzing|parsing|building|compiling|initializing|setup|preparing|progress|executing|stopped|stopping|resumed|resuming|restarted|restarting|closed|queued|removed|sleeping|zombie)\b/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule4,
    backgroundColor: null,
    bold: false,
    italic: false,
    underline: false,
    enabled: true
  },

  // 规则5 - 网络地址
  rule5: {
    title: 'IP地址和端口',
    pattern: /\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?::[1-9]\d{0,4})?\b|(?:(?:[0-9a-fA-F]{1,4}:)*)?::(?:[0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{0,4}|(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule5,
    backgroundColor: null,
    bold: false,
    italic: false,
    underline: false,
    enabled: true
  },

  // 规则6 - URL链接、邮箱地址、文件路径
  rule6: {
    title: 'URL链接和路径',
    pattern: /(?:https?|ftp|ftps|ssh|telnet|ws|wss):\/\/[^\s]+|file:\/\/[^\s]+|mailto:[^\s]+|www\.[^\s]+\.[a-z]{2,}[^\s]*|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|(?<=^|\s)(?:[/~]|\.\.?\/)[a-zA-Z0-9_\-./]+|(?<=^|\s)[A-Z]:\\[a-zA-Z0-9_\-.\\\s]+/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule6,
    backgroundColor: null,
    bold: false,
    italic: false,
    underline: true,
    enabled: true
  },

  // 规则7 - 日期时间格式
  rule7: {
    title: '日期时间',
    pattern: /\b\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:[Tt\s]\d{1,2}:\d{1,2}(?::\d{1,2})?(?:\.\d+)?[Zz]?)?\b|\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b|\b(?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?(?:\.\d+)?(?:\s?[AaPp][Mm])?\b|\[\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}(?:\.\d+)?\]|\b\d{10,13}\b/,
    flags: 'gi',
    fullLine: false,
    displayColor: '#ffffff',
    backgroundColor: '#fa541c',
    bold: false,
    italic: false,
    underline: false,
    enabled: true
  },

  // 规则8 - 带单位的数据
  rule8: {
    title: '数据和单位',
    pattern: /\b\d+(?:\.\d+)?\s*(?:TiB|GiB|MiB|KiB|TB|GB|MB|KB|Tbps|Gbps|Mbps|Kbps|bps|ns|μs|ms|min|hrs?|°C|°F|Hz|KHz|MHz|GHz|THz|mV|kV|mA|kA|mW|kW|MW|GW|fps|rpm|RPM|dpi|ppi|px|bits?|bytes?|cores?|threads?)\b|\b(?:\d+(?:\.\d+)?|100(?:\.0+)?)\s*%|\b\d+(?:\.\d+)?\s*(?:ops[/]s|req[/]s|qps|tps|rps|iops|IOPS|pps|PPS)\b|\b\d+(?:\.\d+)?\s+(?:milliseconds?|seconds?|minutes?|hours?|days?|weeks?|months?|years?)\b/,
    flags: 'gi',
    fullLine: false,
    displayColor: DEFAULT_COLOR_MAPPING.rule8,
    backgroundColor: null,
    bold: false,
    italic: false,
    underline: false,
    enabled: true
  }
}

export class TerminalHighlighter {
  // ANSI序列正则表达式
  // eslint-disable-next-line no-control-regex
  static ANSI_DETECT = /\x1b\[/
  // eslint-disable-next-line no-control-regex
  static ANSI_FULL = /\x1b\[[0-9;]*[mGKH]|\x1b\[[?0-9;]*[lh]|\x1b\[[0-9]*[ABCD]|\x1b\[2J|\x1b\[H|\x1b\[K|\x1b>|\x1b\[7m|\x1b\[27m/g

  constructor(terminal, options = {}) {
    this.terminal = terminal
    this.enabled = options.enabled !== false
    this.debugMode = options.debugMode || false

    // 自定义规则
    this.customRules = options.customRules || null

    // 编译规则（按flags分组的合并正则）
    const compiled = this.compileRules()
    this.mergedPatterns = compiled.mergedPatterns

    if (this.debugMode) {
      console.log('已初始化终端高亮器')
      const totalRules = this.mergedPatterns.reduce((sum, group) =>
        sum + Object.keys(group.ruleMap).length, 0)
      console.log('已启用规则数:', totalRules)
    }
  }

  // 预编译合并的规则 - 按flags分组
  compileRules() {
    const rulesToUse = this.customRules || HIGHLIGHT_RULES

    // 按 flags 分组
    const rulesByFlags = {}

    for (const [name, rule] of Object.entries(rulesToUse)) {
      // 跳过禁用的规则
      if (rule.enabled === false) {
        continue
      }

      // 使用通用方法处理pattern
      const patternSource = this.extractPatternSource(rule)
      if (!patternSource) {
        console.warn(`跳过无效的规则 ${ name }:`, rule.pattern)
        continue
      }

      const flags = rule.flags || 'gi'

      if (!rulesByFlags[flags]) {
        rulesByFlags[flags] = {
          patterns: [],
          rules: []
        }
      }

      rulesByFlags[flags].patterns.push(`(${ patternSource })`)
      rulesByFlags[flags].rules.push({
        name,
        displayColor: rule.displayColor,
        backgroundColor: rule.backgroundColor,
        bold: rule.bold,
        italic: rule.italic,
        underline: rule.underline
      })
    }

    // 为每组flags创建合并的正则
    const mergedPatterns = []

    for (const [flags, group] of Object.entries(rulesByFlags)) {
      if (group.patterns.length === 0) continue

      const mergedPatternSource = group.patterns.join('|')
      const mergedPattern = new RegExp(mergedPatternSource, flags)

      // 创建规则映射（捕获组索引 -> 规则）
      const ruleMap = {}
      group.rules.forEach((rule, index) => {
        ruleMap[index + 1] = rule
      })

      mergedPatterns.push({
        pattern: mergedPattern,
        ruleMap,
        flags
      })
    }

    if (this.debugMode) {
      console.log('合并正则分组数:', mergedPatterns.length)
      mergedPatterns.forEach(group => {
        console.log(`  flags=${ group.flags }, 规则数=${ Object.keys(group.ruleMap).length }`)
      })
    }

    return { mergedPatterns }
  }

  // 提取并处理规则的pattern源码
  extractPatternSource(rule) {
    let patternSource = ''

    if (rule.pattern instanceof RegExp) {
      patternSource = rule.pattern.source
    } else if (rule.pattern && rule.pattern.source) {
      patternSource = rule.pattern.source
    } else {
      return null
    }

    // 如果启用了fullLine，扩展模式到行尾
    if (rule.fullLine) {
      patternSource = `(?:${ patternSource }).*?(?=\\r?\\n|$)`
    }

    return patternSource
  }

  // 更新自定义规则
  updateCustomRules(customRules) {
    this.customRules = customRules

    // 重新编译规则
    const compiled = this.compileRules()
    this.mergedPatterns = compiled.mergedPatterns

    if (this.debugMode) {
      const totalRules = this.mergedPatterns.reduce((sum, group) =>
        sum + Object.keys(group.ruleMap).length, 0)
      console.log('规则已更新，启用规则数:', totalRules)
    }
  }

  // 主要的高亮方法
  highlightText(text) {
    if (!this.enabled || !text) {
      return text
    }

    // 跳过空白、极短文本、纯符号文本
    if (this.shouldSkip(text)) {
      if (this.debugMode) {
        console.log('跳过特殊文本:', JSON.stringify(text))
      }
      return text
    }

    // 检查是否包含ANSI序列
    if (this.hasAnsiSequences(text)) {
      // 如果文本主要是控制序列（如光标移动、清屏等），则跳过
      if (this.isControlSequenceOnly(text)) {
        if (this.debugMode) {
          console.log('跳过控制序列文本:', text.replace(/\x1b/g, '\\x1b'))
        }
        return text
      }

      // 对于包含少量ANSI但有实际内容的文本，尝试着去处理
      try {
        const result = this.applyRulesWithAnsi(text)
        if (this.debugMode && result !== text) {
          console.log('原始文本 (含ANSI):', text.replace(/\x1b/g, '\\x1b'))
          console.log('高亮后:', result.replace(/\x1b/g, '\\x1b'))
        }
        return result
      } catch (error) {
        if (this.debugMode) {
          console.log('ANSI文本处理失败，保持原样:', text.replace(/\x1b/g, '\\x1b'))
        }
        return text
      }
    }

    try {
      const highlightedText = this.applyRules(text)

      if (this.debugMode && text !== highlightedText) {
        console.log('原始文本:', JSON.stringify(text))
        console.log('高亮后:', highlightedText.replace(/\x1b/g, '\\x1b'))
      }

      return highlightedText
    } catch (error) {
      console.error('高亮处理失败:', error)
      return text
    }
  }

  // 检测ANSI序列
  hasAnsiSequences(text) {
    return TerminalHighlighter.ANSI_DETECT.test(text)
  }

  // 检查是否主要是控制序列
  isControlSequenceOnly(text) {
    // 移除ANSI序列后，如果剩余内容很少，则认为是控制序列
    const cleanText = text.replace(TerminalHighlighter.ANSI_FULL, '').trim()
    return cleanText.length < 3 || /^[\s\r\n]*$/.test(cleanText)
  }

  // 处理包含ANSI序列的文本，保护现有的ANSI序列，只对纯文本部分应用高亮
  applyRulesWithAnsi(text) {
    // 分离ANSI序列和纯文本
    const parts = []
    let lastIndex = 0

    // 使用全局正则匹配ANSI序列
    const matches = text.matchAll(TerminalHighlighter.ANSI_FULL)

    for (const match of matches) {
      // 添加ANSI序列之前的文本
      if (match.index > lastIndex) {
        const textPart = text.slice(lastIndex, match.index)
        if (textPart) {
          parts.push({ type: 'text', content: textPart })
        }
      }

      // 添加ANSI序列
      parts.push({ type: 'ansi', content: match[0] })
      lastIndex = match.index + match[0].length
    }

    // 添加最后剩余的文本
    if (lastIndex < text.length) {
      const textPart = text.slice(lastIndex)
      if (textPart) {
        parts.push({ type: 'text', content: textPart })
      }
    }

    // 对纯文本部分应用高亮规则
    let result = ''
    for (const part of parts) {
      if (part.type === 'ansi') {
        result += part.content
      } else {
        const highlighted = this.applyRules(part.content)
        result += highlighted
      }
    }

    return result
  }

  // 判断是否跳过处理
  shouldSkip(text) {
    // 跳过空文本
    if (!text.trim()) return true

    // 跳过极短文本
    if (text.length < 3) return true

    // 跳过纯符号文本
    if (/^[\W_]+$/.test(text)) return true

    return false
  }

  // 应用所有规则 - 使用分组合并的正则
  applyRules(text) {
    if (!this.mergedPatterns || this.mergedPatterns.length === 0) {
      return text // 没有启用的规则
    }

    let result = text

    // 依次应用每个flags分组的合并正则
    for (const group of this.mergedPatterns) {
      result = result.replace(group.pattern, (...args) => {
        const match = args[0]

        // 避免重复高亮已包含ANSI序列的匹配
        if (TerminalHighlighter.ANSI_DETECT.test(match)) {
          return match
        }

        // 找到匹配的捕获组
        const groups = args.slice(1, -2)

        // 找到第一个非undefined的捕获组
        for (let i = 0; i < groups.length; i++) {
          if (groups[i] !== undefined) {
            const rule = group.ruleMap[i + 1]
            if (rule) {
              return this.applyStyle(match, rule)
            }
            break
          }
        }

        return match
      })
    }

    return result
  }

  // 应用样式到匹配文本
  applyStyle(text, rule) {
    let styleString = ''

    // 先添加背景色
    if (rule.backgroundColor) {
      const bgColor = this.getBackgroundColorCode(rule.backgroundColor)
      if (bgColor) {
        styleString += bgColor
      }
    }

    // 添加文字样式
    if (rule.bold) styleString += TEXT_STYLES.BOLD
    if (rule.italic) styleString += TEXT_STYLES.ITALIC
    if (rule.underline) styleString += TEXT_STYLES.UNDERLINE

    // 添加文本颜色
    if (rule.displayColor) {
      const textColor = this.getTextColorCode(rule.displayColor)
      if (textColor) {
        styleString += textColor
      }
    }

    return `${styleString}${text}${TEXT_STYLES.RESET}`
  }

  // 获取文本颜色 ANSI 代码
  getTextColorCode(hexColor) {
    if (!hexColor) return ''

    // 将十六进制颜色转换为 RGB
    const rgb = this.hexToRgb(hexColor)
    if (!rgb) return ''

    // 使用 RGB 模式 (38;2;r;g;b) 38=前景色(文本), 48=背景色
    return `\x1b[38;2;${ rgb.r };${ rgb.g };${ rgb.b }m`
  }

  // 获取背景色 ANSI 代码
  getBackgroundColorCode(hexColor) {
    if (!hexColor) return ''

    // 将十六进制颜色转换为 RGB
    const rgb = this.hexToRgb(hexColor)
    if (!rgb) return ''

    // 使用 RGB 模式 (48;2;r;g;b) 38=前景色(文本), 48=背景色
    return `\x1b[48;2;${ rgb.r };${ rgb.g };${ rgb.b }m`
  }

  // 十六进制颜色转 RGB
  hexToRgb(hex) {
    if (!hex) return null

    // 移除 # 符号
    hex = hex.replace('#', '')

    // 简写形式的hex
    if (hex.length === 3) {
      hex = hex.split('').map(char => char + char).join('')
    }

    if (hex.length !== 6) return null

    return {
      r: parseInt(hex.substring(0, 2), 16),
      g: parseInt(hex.substring(2, 4), 16),
      b: parseInt(hex.substring(4, 6), 16)
    }
  }

  // 启用/禁用高亮
  setEnabled(enabled) {
    this.enabled = enabled
  }

  // 启用/禁用调试模式
  setDebugMode(debugMode) {
    this.debugMode = debugMode
    if (debugMode) {
      console.log('终端高亮调试模式已启用')
    } else {
      console.log('终端高亮调试模式已禁用')
    }
  }

  // 应用单个规则的HTML预览
  applySingleRuleForHtml(text, rule) {
    try {
      // 使用通用方法获取pattern源码
      const patternSource = this.extractPatternSource(rule)
      if (!patternSource) {
        return '正则表达式格式错误'
      }

      const flags = rule.flags || 'gi'
      const regex = new RegExp(patternSource, flags)

      return text.replace(regex, (match) => {
        return this.applyHtmlStyle(match, rule)
      })
    } catch (error) {
      return `正则表达式错误: ${ error.message }`
    }
  }

  // 为HTML应用样式
  applyHtmlStyle(text, rule) {
    let styleProps = ''

    // 字体设置
    styleProps += 'font-family: monospace !important;'
    styleProps += 'font-size: 14px !important;'

    // 文字样式
    styleProps += 'font-weight: ' + (rule.bold ? 'bold' : 'normal') + ' !important;'
    styleProps += 'font-style: ' + (rule.italic ? 'italic' : 'normal') + ' !important;'

    // 文本颜色
    if (rule.displayColor) {
      styleProps += ` color: ${ rule.displayColor } !important;`
    }

    // 背景色
    if (rule.backgroundColor) {
      styleProps += ` background-color: ${ rule.backgroundColor } !important;`
    }

    // 下划线
    if (rule.underline) {
      styleProps += ' text-decoration: underline !important;'
    }

    // 基础样式
    styleProps += ' padding: 2px 4px !important; border-radius: 3px !important;'

    return `<span style="${ styleProps }">${ text }</span>`
  }
}
