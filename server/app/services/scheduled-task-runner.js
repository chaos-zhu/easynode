import ssh2Module from 'ssh2'
import { getConnectionOptions, handleProxyAndJumpHostConnection } from '../socket/terminal.js'

const { Client: SSHClient } = ssh2Module

export const SCHEDULED_TASK_OUTPUT_LIMIT = 256 * 1024

const TIMEOUT_PHASE_LABELS = {
  connection_options: '读取 SSH 连接配置',
  proxy_connection: '建立代理或跳板机连接',
  ssh_connection: 'SSH 连接与认证',
  command_start: '启动脚本',
  script_execution: '脚本执行'
}

function decodeWithinAllocatedBytes(chunks) {
  const buffer = Buffer.concat(chunks)
  let value = buffer.toString('utf8')
  if (Buffer.byteLength(value, 'utf8') <= buffer.length) return value
  while (value && Buffer.byteLength(value, 'utf8') > buffer.length) value = value.slice(0, -1)
  return value
}

export function createOutputCollector(limit = SCHEDULED_TASK_OUTPUT_LIMIT) {
  let collected = 0
  let truncated = false
  const stdoutChunks = []
  const stderrChunks = []

  const append = (chunks, value) => {
    const chunk = Buffer.isBuffer(value) ? value : Buffer.from(value)
    const remaining = limit - collected
    if (remaining <= 0) {
      truncated = true
      return
    }
    if (chunk.length > remaining) {
      chunks.push(chunk.subarray(0, remaining))
      collected += remaining
      truncated = true
      return
    }
    chunks.push(chunk)
    collected += chunk.length
  }

  return {
    appendStdout: value => append(stdoutChunks, value),
    appendStderr: value => append(stderrChunks, value),
    result: () => ({
      stdout: decodeWithinAllocatedBytes(stdoutChunks),
      stderr: decodeWithinAllocatedBytes(stderrChunks),
      truncated,
      bytes: collected
    })
  }
}

function closeResource(resource) {
  for (const method of ['signal', 'close', 'end', 'destroy']) {
    if (typeof resource?.[method] !== 'function') continue
    try {
      if (method === 'signal') resource[method]('KILL')
      else resource[method]()
    } catch {
      // 资源可能已经由 SSH 库关闭。
    }
  }
}

export function buildScheduledScriptCommand(command, useBase64 = false) {
  const script = String(command || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  if (!useBase64) return `export DEBIAN_FRONTEND=noninteractive; ${ script }`
  const encoded = Buffer.from(script, 'utf8').toString('base64')
  return [
    'export DEBIAN_FRONTEND=noninteractive',
    'tmp_script=$(mktemp /tmp/easynode-scheduled-XXXXXX.sh) || exit 1',
    'trap \'rm -f "$tmp_script"\' EXIT INT TERM',
    `printf '%s' '${ encoded }' | base64 -d > "$tmp_script"`,
    'chmod +x "$tmp_script"',
    'bash "$tmp_script"',
    'script_status=$?',
    'rm -f "$tmp_script"',
    'trap - EXIT INT TERM',
    'exit "$script_status"'
  ].join('; ')
}

/**
 * 为一次定时任务执行建立独立 SSH 连接。超时覆盖凭据解析、代理/跳板机、
 * SSH 握手和脚本执行的完整生命周期。
 */
export function executeScheduledHost({ host, command, useBase64, timeoutSeconds, signal, adapters = {} }) {
  const startedAt = Date.now()
  const timeoutMs = timeoutSeconds * 1000
  const loadConnectionOptions = adapters.getConnectionOptions || getConnectionOptions
  const connectProxyAndJumpHosts = adapters.handleProxyAndJumpHostConnection || handleProxyAndJumpHostConnection
  const createClient = adapters.createClient || (() => new SSHClient())

  return new Promise((resolve) => {
    let settled = false
    let timedOut = false
    let stream = null
    let client = null
    let proxySocket = null
    let jumpClients = []
    let phase = 'connection_options'
    const output = createOutputCollector()

    const cleanup = () => {
      clearTimeout(timer)
      if (signal) signal.removeEventListener('abort', onAbort)
      closeResource(stream)
      closeResource(client)
      closeResource(proxySocket)
      jumpClients.forEach(closeResource)
    }

    const finish = (status, extra = {}) => {
      if (settled) return
      settled = true
      cleanup()
      const collectedOutput = output.result()
      resolve({
        status,
        stdout: collectedOutput.stdout,
        stderr: collectedOutput.stderr,
        truncated: collectedOutput.truncated,
        durationMs: Date.now() - startedAt,
        startedAt,
        endedAt: Date.now(),
        ...extra
      })
    }

    const onAbort = () => {
      const timeoutPhase = timedOut ? phase : null
      finish(timedOut ? 'timeout' : 'cancelled', {
        exitCode: null,
        signal: timedOut ? 'TIMEOUT' : 'CANCELLED',
        timeoutPhase,
        error: timedOut
          ? `${ TIMEOUT_PHASE_LABELS[timeoutPhase] || '任务执行' }阶段超时（总限时 ${ timeoutSeconds } 秒）`
          : '用户停止了执行'
      })
    }

    const timer = setTimeout(() => {
      timedOut = true
      onAbort()
    }, timeoutMs)

    if (signal) {
      if (signal.aborted) return onAbort()
      signal.addEventListener('abort', onAbort, { once: true })
    }

    (async () => {
      try {
        const { authInfo, hostInfo } = await loadConnectionOptions(host._id)
        if (settled) return

        phase = 'proxy_connection'
        const proxyResult = await connectProxyAndJumpHosts({
          hostInfo,
          targetConnectionOptions: authInfo,
          socket: null,
          logPrefix: 'Scheduled task '
        })
        proxySocket = proxyResult.targetConnectionOptions?.sock || null
        jumpClients = proxyResult.jumpSshClients || []
        if (settled) {
          cleanup()
          return
        }

        const targetOptions = proxyResult.targetConnectionOptions
        phase = 'ssh_connection'
        client = createClient()
        client
          .once('ready', () => {
            if (settled) return
            phase = 'command_start'
            const executed = buildScheduledScriptCommand(command, useBase64)
            client.exec(executed, (error, execStream) => {
              if (settled) {
                closeResource(execStream)
                return
              }
              if (error) {
                finish('failed', { exitCode: null, error: `命令执行失败: ${ error.message }` })
                return
              }
              phase = 'script_execution'
              stream = execStream
              stream
                .on('data', chunk => output.appendStdout(chunk))
                .once('error', streamError => {
                  finish('failed', { exitCode: null, error: `命令流错误: ${ streamError.message }` })
                })
                .once('close', (code, signalName) => {
                  const exitCode = typeof code === 'number' ? code : null
                  finish(exitCode === 0 ? 'success' : 'failed', {
                    exitCode,
                    signal: signalName || null,
                    error: exitCode === 0 ? '' : `脚本退出码: ${ exitCode ?? '未知' }`
                  })
                })
              stream.stderr.on('data', chunk => output.appendStderr(chunk))
            })
          })
          .once('error', error => {
            finish('failed', { exitCode: null, error: `SSH 连接失败: ${ error.message }` })
          })
          .on('keyboard-interactive', (name, instructions, lang, prompts, done) => {
            done([targetOptions[targetOptions.authType] || targetOptions.password || ''])
          })
          .connect({
            ...targetOptions,
            tryKeyboard: true,
            readyTimeout: Math.max(1000, timeoutMs - (Date.now() - startedAt))
          })
      } catch (error) {
        finish('failed', { exitCode: null, error: error.message || String(error) })
      }
    })()
  })
}
