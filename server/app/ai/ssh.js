/**
 * Agent 的 SSH 执行层
 *
 * 与终端 socket 的区别：这里走 exec 通道而不是 PTY。
 * PTY 里混杂 ANSI 转义、提示符、用户正在编辑的半行命令，喂给模型全是噪声，
 * 且无法可靠判断命令何时结束、退出码是多少。exec 通道能拿到干净的
 * stdout / stderr / exitCode。
 *
 * 连接复用：一个 turn 内模型可能连续执行十几条命令，每条都重连太慢。
 * 按 hostId 池化，空闲超时后回收。
 */

import ssh2Module from 'ssh2'
import { getConnectionOptions, handleProxyAndJumpHostConnection } from '../socket/terminal.js'
import { HostListDB } from '../utils/db-class.js'

const { Client: SSHClient } = ssh2Module
const hostListDB = new HostListDB().getInstance()

// 空闲连接保留时长
const IDLE_TTL_MS = 5 * 60 * 1000
// 单条命令默认超时
export const DEFAULT_TIMEOUT_MS = 60 * 1000
export const MAX_TIMEOUT_MS = 30 * 60 * 1000
// 单条命令最多收集的输出字节数，防止 `cat 大文件` 打爆内存
const MAX_COLLECT_BYTES = 2 * 1024 * 1024

/** hostId -> { client, jumpClients, refCount, idleTimer, connecting } */
const pool = new Map()

function clearIdleTimer(entry) {
  if (entry.idleTimer) {
    clearTimeout(entry.idleTimer)
    entry.idleTimer = null
  }
}

function scheduleIdleClose(hostId) {
  const entry = pool.get(hostId)
  if (!entry) return
  clearIdleTimer(entry)
  entry.idleTimer = setTimeout(() => {
    if (entry.refCount > 0) return
    closeEntry(hostId, entry)
  }, IDLE_TTL_MS)
}

function closeEntry(hostId, entry) {
  pool.delete(hostId)
  clearIdleTimer(entry)
  try {
    entry.client?.end()
  } catch {
    // 忽略关闭异常
  }
  entry.jumpClients?.forEach((client) => {
    try {
      client?.end()
    } catch {
      // 忽略
    }
  })
}

/** 建立一条新的 SSH 连接（含代理与跳板机） */
async function connect(hostId) {
  const hostInfo = await hostListDB.findOneAsync({ _id: hostId })
  if (!hostInfo) throw new Error(`未找到主机: ${ hostId }`)

  const { authInfo } = await getConnectionOptions(hostId)

  let jumpClients = []
  const proxyResult = await handleProxyAndJumpHostConnection({
    hostInfo,
    targetConnectionOptions: authInfo,
    socket: null,
    logPrefix: 'AI Agent '
  })
  jumpClients = proxyResult?.jumpSshClients || []

  const client = await new Promise((resolve, reject) => {
    const sshClient = new SSHClient()
    const onError = (err) => {
      jumpClients.forEach((item) => item?.end())
      reject(new Error(`SSH 连接失败: ${ err.message }`))
    }
    sshClient
      .on('ready', () => resolve(sshClient))
      .on('error', onError)
      .on('keyboard-interactive', (name, instructions, lang, prompts, finish) => {
        finish([authInfo[hostInfo.authType]])
      })
      .connect({ tryKeyboard: true, ...authInfo })
  })

  // 连接被对端关闭时从池里摘掉，避免下次拿到死连接
  client.on('close', () => {
    const entry = pool.get(hostId)
    if (entry?.client === client) closeEntry(hostId, entry)
  })

  return { client, jumpClients, hostInfo }
}

/**
 * 取得一条可用连接。调用方必须在用完后调用 release()。
 */
async function acquire(hostId) {
  let entry = pool.get(hostId)

  if (entry?.connecting) {
    await entry.connecting
    entry = pool.get(hostId)
  }

  if (!entry || !entry.client) {
    const placeholder = { client: null, jumpClients: [], refCount: 0, idleTimer: null, connecting: null }
    placeholder.connecting = connect(hostId)
      .then(({ client, jumpClients, hostInfo }) => {
        placeholder.client = client
        placeholder.jumpClients = jumpClients
        placeholder.hostInfo = hostInfo
        placeholder.connecting = null
        return placeholder
      })
      .catch((error) => {
        pool.delete(hostId)
        throw error
      })
    pool.set(hostId, placeholder)
    await placeholder.connecting
    entry = pool.get(hostId)
  }

  if (!entry?.client) throw new Error(`SSH 连接不可用: ${ hostId }`)

  entry.refCount += 1
  clearIdleTimer(entry)

  return {
    client: entry.client,
    hostInfo: entry.hostInfo,
    release: () => {
      entry.refCount = Math.max(0, entry.refCount - 1)
      if (entry.refCount === 0) scheduleIdleClose(hostId)
    }
  }
}

/**
 * 主动断开某台主机的 agent 连接。
 *
 * 必须尊重 refCount：连接是按 hostId 池化的，同一台主机可能正被另一个
 * 会话用着。直接 close 会把别人正在跑的命令掐断。还有人在用时改为
 * 重排空闲回收，等最后一个使用者释放后自然关闭。
 */
export function disconnect(hostId) {
  const entry = pool.get(hostId)
  if (!entry) return
  if (entry.refCount > 0) {
    scheduleIdleClose(hostId)
    return
  }
  closeEntry(hostId, entry)
}

/** 断开全部 agent 连接（进程退出或用户结束会话时调用） */
export function disconnectAll() {
  for (const [hostId, entry] of pool.entries()) closeEntry(hostId, entry)
}

/**
 * 包装命令：注入非交互环境变量，可选切换工作目录。
 *
 * 审计日志同时记录原始命令与包装后的命令，避免"用户批准的是 A、
 * 实际执行的是 B"这种说不清的情况。
 */
/**
 * 单引号转义。
 *
 * ⚠️ 不要用 JSON.stringify 代替：它产出的是双引号字符串，而双引号里
 * `$(...)`、反引号、`$VAR` 仍会被 shell 展开。单引号才是字面量，
 * 内部的单引号用 '\'' 的方式断开拼接。
 */
export function shellQuote(value) {
  return `'${ String(value).replace(/'/g, '\'\\\'\'') }'`
}

export function wrapCommand(command, { cwd, nonInteractive = true } = {}) {
  const parts = []
  if (nonInteractive) parts.push('export DEBIAN_FRONTEND=noninteractive')
  if (cwd) parts.push(`cd ${ shellQuote(cwd) }`)
  parts.push(command)
  return parts.join(' && ')
}

/**
 * 在指定主机上执行一条命令。
 *
 * @param {string} hostId
 * @param {string} command
 * @param {object} [options]
 * @param {number} [options.timeoutMs]
 * @param {string} [options.cwd]
 * @param {AbortSignal} [options.signal] 用户点击停止时中断
 * @returns {Promise<{stdout,stderr,exitCode,signal,timedOut,truncated,durationMs,executed}>}
 */
export async function execCommand(hostId, command, options = {}) {
  const timeoutMs = Math.min(Math.max(options.timeoutMs || DEFAULT_TIMEOUT_MS, 1000), MAX_TIMEOUT_MS)
  const executed = wrapCommand(command, options)
  const startedAt = Date.now()

  const { client, release } = await acquire(hostId)

  try {
    return await new Promise((resolve, reject) => {
      let stdout = ''
      let stderr = ''
      let collected = 0
      let truncated = false
      let settled = false
      let timedOut = false
      let stream = null
      let timer = null
      let onAbort = null

      const cleanup = () => {
        if (timer) clearTimeout(timer)
        if (onAbort && options.signal) options.signal.removeEventListener('abort', onAbort)
      }

      const finish = (result) => {
        if (settled) return
        settled = true
        cleanup()
        resolve({ ...result, stdout, stderr, truncated, timedOut, durationMs: Date.now() - startedAt, executed })
      }

      const fail = (error) => {
        if (settled) return
        settled = true
        cleanup()
        reject(error)
      }

      const append = (target, chunk) => {
        if (collected >= MAX_COLLECT_BYTES) {
          truncated = true
          return target
        }
        const text = chunk.toString('utf8')
        collected += Buffer.byteLength(text)
        if (collected > MAX_COLLECT_BYTES) truncated = true
        return target + text
      }

      const kill = () => {
        try {
          stream?.signal('KILL')
          stream?.close()
        } catch {
          // 通道可能已关闭
        }
      }

      timer = setTimeout(() => {
        timedOut = true
        kill()
        finish({ exitCode: null, signal: 'TIMEOUT' })
      }, timeoutMs)

      if (options.signal) {
        if (options.signal.aborted) return fail(new Error('已取消'))
        onAbort = () => {
          kill()
          finish({ exitCode: null, signal: 'ABORTED' })
        }
        options.signal.addEventListener('abort', onAbort, { once: true })
      }

      client.exec(executed, (err, execStream) => {
        if (err) return fail(new Error(`命令执行失败: ${ err.message }`))
        stream = execStream

        stream
          .on('close', (code, signalName) => {
            finish({ exitCode: typeof code === 'number' ? code : null, signal: signalName || null })
          })
          .on('data', (chunk) => {
            stdout = append(stdout, chunk)
          })
          .on('error', (streamErr) => fail(new Error(`命令流错误: ${ streamErr.message }`)))

        stream.stderr.on('data', (chunk) => {
          stderr = append(stderr, chunk)
        })
      })
    })
  } finally {
    release()
  }
}

/** 打开一个 SFTP 会话，回调结束后自动释放 */
export async function withSftp(hostId, handler) {
  const { client, release } = await acquire(hostId)
  let sftp = null
  try {
    sftp = await new Promise((resolve, reject) => {
      client.sftp((err, session) => (err ? reject(new Error(`SFTP 打开失败: ${ err.message }`)) : resolve(session)))
    })
    return await handler(sftp)
  } finally {
    try {
      sftp?.end()
    } catch {
      // 忽略
    }
    release()
  }
}
