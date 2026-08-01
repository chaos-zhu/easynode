/**
 * 极简 shell 词法解析器
 *
 * 目的不是完整实现 POSIX shell 语法，而是让安全判定拿到**结构化**的命令，
 * 而不是对整行文本套正则 —— 后者对 `X="-rf /"; rm $X` 这类写法毫无办法。
 *
 * 提供的能力：
 *   1. 按 ; && || | & 换行 分段，且不会被引号内的同名字符误导
 *   2. 每段拆出 argv、重定向目标
 *   3. 标记该段是否含有无法静态求值的动态构造（变量、子 shell、反引号）
 *
 * 未覆盖（有意为之，交给上层按 high 处理）：
 *   here-doc、进程替换的内部结构、别名展开、函数定义。
 */

const OPERATORS = ['||', '&&', ';;', ';', '|', '&', '\n']
/**
 * 把命令行切成 token。
 * 返回 { tokens, dynamic } —— token 为 { type: 'word'|'op', value, quoted }
 */
function tokenize(input) {
  const tokens = []
  let current = null
  let dynamic = false
  let i = 0

  const pushWord = (value, quoted) => {
    if (current) {
      current.value += value
      current.quoted = current.quoted && quoted
    } else {
      current = { type: 'word', value, quoted }
    }
  }

  const flushWord = () => {
    if (current) {
      tokens.push(current)
      current = null
    }
  }

  while (i < input.length) {
    const char = input[i]

    // 反斜杠转义
    if (char === '\\') {
      if (i + 1 < input.length) {
        pushWord(input[i + 1], true)
        i += 2
      } else {
        i += 1
      }
      continue
    }

    // 单引号：内部完全字面量，$ 不展开
    if (char === '\'') {
      const end = input.indexOf('\'', i + 1)
      if (end === -1) {
        pushWord(input.slice(i + 1), true)
        i = input.length
      } else {
        pushWord(input.slice(i + 1, end), true)
        i = end + 1
      }
      continue
    }

    // 双引号：内部 $ 仍会展开
    if (char === '"') {
      const { value, end, hasExpansion } = readDoubleQuoted(input, i)
      if (hasExpansion) dynamic = true
      pushWord(value, !hasExpansion)
      i = end
      continue
    }

    // 反引号命令替换
    if (char === '`') {
      dynamic = true
      const end = input.indexOf('`', i + 1)
      pushWord(input.slice(i, end === -1 ? input.length : end + 1), false)
      i = end === -1 ? input.length : end + 1
      continue
    }

    // $( ) 命令替换 / $(( )) 算术展开 / ${...} / $VAR
    if (char === '$') {
      dynamic = true
      const { value, end } = readDollar(input, i)
      pushWord(value, false)
      i = end
      continue
    }

    // <( ) >( ) 进程替换
    if ((char === '<' || char === '>') && input[i + 1] === '(') {
      dynamic = true
      const end = matchParen(input, i + 1)
      pushWord(input.slice(i, end), false)
      i = end
      continue
    }

    // 空白
    if (/\s/.test(char) && char !== '\n') {
      flushWord()
      i += 1
      continue
    }

    // 文件描述符合并，例如 2>&1 / 1>&2。它不读写文件，必须在通用
    // 操作符判断之前整体识别，否则会被错误拆成 `>` 和后台执行符 `&`。
    const fdRedirect = /^(\d*)(>>?|<)&(\d+|-)/.exec(input.slice(i))
    if (fdRedirect) {
      flushWord()
      tokens.push({
        type: 'fd_redirect',
        op: fdRedirect[2],
        target: `&${ fdRedirect[3] }`,
        fd: fdRedirect[1] || undefined
      })
      i += fdRedirect[0].length
      continue
    }

    // 带文件描述符的普通重定向，例如 2>/dev/null。目标仍由后续 token
    // 读取，这里只把紧邻操作符的数字识别为 fd，避免落入 argv。
    const numberedRedirect = current
      ? null
      : /^(\d+)(>>?|<)(?![>&])/.exec(input.slice(i))
    if (numberedRedirect) {
      flushWord()
      tokens.push({
        type: 'redirect',
        value: numberedRedirect[2],
        fd: numberedRedirect[1]
      })
      i += numberedRedirect[0].length
      continue
    }

    // 操作符
    const op = OPERATORS.find((item) => input.startsWith(item, i))
    if (op) {
      flushWord()
      tokens.push({ type: 'op', value: op })
      i += op.length
      continue
    }

    // 重定向符号需要独立成 token，便于识别目标
    if (char === '>' || char === '<') {
      const double = input.startsWith('>>', i)
      flushWord()
      tokens.push({ type: 'redirect', value: double ? '>>' : char })
      i += double ? 2 : 1
      continue
    }

    pushWord(char, true)
    i += 1
  }

  flushWord()
  return { tokens, dynamic }
}

/** 读取双引号字符串，返回内容与是否含展开 */
function readDoubleQuoted(input, start) {
  let i = start + 1
  let value = ''
  let hasExpansion = false
  while (i < input.length) {
    const char = input[i]
    if (char === '\\' && i + 1 < input.length) {
      value += input[i + 1]
      i += 2
      continue
    }
    if (char === '"') {
      i += 1
      break
    }
    if (char === '$' || char === '`') hasExpansion = true
    value += char
    i += 1
  }
  return { value, end: i, hasExpansion }
}

/** 读取 $ 开头的展开结构，原样返回文本 */
function readDollar(input, start) {
  if (input[start + 1] === '(') {
    const end = matchParen(input, start + 1)
    return { value: input.slice(start, end), end }
  }
  if (input[start + 1] === '{') {
    const end = input.indexOf('}', start)
    const stop = end === -1 ? input.length : end + 1
    return { value: input.slice(start, stop), end: stop }
  }
  const match = /^\$[A-Za-z_][A-Za-z0-9_]*|^\$[@*#?$!0-9-]/.exec(input.slice(start))
  const length = match ? match[0].length : 1
  return { value: input.slice(start, start + length), end: start + length }
}

/** 找到与 input[open] 处 '(' 配对的 ')' 的下一个下标 */
function matchParen(input, open) {
  let depth = 0
  for (let i = open; i < input.length; i += 1) {
    if (input[i] === '(') depth += 1
    else if (input[i] === ')') {
      depth -= 1
      if (depth === 0) return i + 1
    }
  }
  return input.length
}

/**
 * 命令行 → 分段结构
 *
 * @param {string} input
 * @returns {Array<{ argv: string[], quotedFlags: boolean[], redirects: Array<{op:string,target:string}>,
 *                   dynamic: boolean, raw: string, connector: string|null }>}
 */
export function parseCommandLine(input) {
  if (typeof input !== 'string' || !input.trim()) return []

  const { tokens, dynamic } = tokenize(input)
  const segments = []
  let currentArgv = []
  let currentQuoted = []
  let currentRedirects = []
  let connector = null
  let pendingRedirect = null

  const flushSegment = () => {
    if (currentArgv.length || currentRedirects.length) {
      segments.push({
        argv: currentArgv,
        quotedFlags: currentQuoted,
        redirects: currentRedirects,
        // 动态标记按整行传播：无法静态确定哪一段引用了变量
        dynamic,
        raw: currentArgv.join(' '),
        connector
      })
    }
    currentArgv = []
    currentQuoted = []
    currentRedirects = []
  }

  for (const token of tokens) {
    if (token.type === 'op') {
      flushSegment()
      connector = token.value
      continue
    }
    if (token.type === 'redirect') {
      pendingRedirect = { op: token.value, fd: token.fd }
      continue
    }
    if (token.type === 'fd_redirect') {
      currentRedirects.push({
        op: token.op,
        target: token.target,
        fd: token.fd,
        duplicate: true
      })
      continue
    }
    // word
    if (pendingRedirect) {
      const redirect = {
        op: pendingRedirect.op,
        target: token.value
      }
      if (pendingRedirect.fd) redirect.fd = pendingRedirect.fd
      currentRedirects.push(redirect)
      pendingRedirect = null
      continue
    }

    currentArgv.push(token.value)
    currentQuoted.push(token.quoted !== false)
  }

  flushSegment()
  return segments
}

/**
 * 剥离命令前缀包装（sudo / env / nohup / timeout ...），拿到真实执行的命令。
 * 返回 { cmd, args, wrappers } —— cmd 已取 basename。
 */
// 注意：不要把 su 当作 wrapper 剥离。`su -c '<payload>'` 的 payload 必须
// 保留在 args 里，交给 safety.js 递归判定，否则整段会被静默跳过。
const WRAPPERS = new Set([
  'sudo', 'doas', 'env', 'nohup', 'setsid', 'nice', 'ionice',
  'stdbuf', 'timeout', 'time', 'command', 'builtin', 'exec', 'xargs',
  // busybox/toybox 的第一个位置参数才是真正执行的 applet。
  'busybox', 'toybox'
])

// 各 wrapper 需要连带跳过的带值选项
const WRAPPER_VALUE_FLAGS = {
  sudo: new Set(['-u', '-g', '-h', '-p', '-C', '-r', '-t', '-U']),
  doas: new Set(['-u', '-C']),
  timeout: new Set(['-s', '--signal', '-k', '--kill-after']),
  nice: new Set(['-n', '--adjustment']),
  ionice: new Set(['-c', '-n', '-p']),
  stdbuf: new Set(['-i', '-o', '-e']),
  xargs: new Set(['-n', '-P', '-I', '-d', '-s', '-E'])
}

export function unwrapCommand(argv) {
  const wrappers = []
  let index = 0

  while (index < argv.length) {
    const token = argv[index]
    const name = basename(token)
    if (!WRAPPERS.has(name)) break

    wrappers.push(name)
    index += 1

    // 跳过该 wrapper 自身的选项
    const valueFlags = WRAPPER_VALUE_FLAGS[name] || new Set()
    while (index < argv.length) {
      const arg = argv[index]
      if (arg === '--') {
        index += 1
        break
      }
      if (!arg.startsWith('-')) {
        // env / timeout 的位置参数：VAR=value 或超时时长
        if (name === 'env' && /^[A-Za-z_][A-Za-z0-9_]*=/.test(arg)) {
          index += 1
          continue
        }
        if ((name === 'timeout' || name === 'nice' || name === 'xargs') && /^[\d.]+[smhd]?$/.test(arg)) {
          index += 1
          continue
        }
        break
      }
      if (valueFlags.has(arg)) {
        index += 2
        continue
      }
      index += 1
    }
  }

  const rest = argv.slice(index)
  return {
    cmd: rest.length ? basename(rest[0]) : '',
    path: rest.length ? rest[0] : '',
    args: rest.slice(1),
    wrappers
  }
}

export function basename(value) {
  if (typeof value !== 'string') return ''
  const cleaned = value.split('/').pop()
  return cleaned || value
}

/**
 * 展开合并写法的短选项，便于判定等价形式。
 * `-rf` → ['-r', '-f']；长选项原样保留。
 */
export function expandFlags(args) {
  const flags = new Set()
  for (const arg of args) {
    if (arg === '--') break
    if (arg.startsWith('--')) {
      flags.add(arg.split('=')[0])
      continue
    }
    if (arg.startsWith('-') && arg.length > 1) {
      for (const char of arg.slice(1)) flags.add(`-${ char }`)
    }
  }
  return flags
}

/** 取出非选项的位置参数 */
export function positionalArgs(args) {
  const result = []
  let afterDoubleDash = false
  for (const arg of args) {
    if (arg === '--') {
      afterDoubleDash = true
      continue
    }
    if (!afterDoubleDash && arg.startsWith('-') && arg.length > 1) continue
    result.push(arg)
  }
  return result
}
