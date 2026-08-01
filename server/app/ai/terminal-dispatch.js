import { randomUUID } from 'node:crypto'

// 长任务由终端侧的命令边界协议判断完成；这里仅防止浏览器或会话失联后
// 无限悬挂。持续输出的 docker pull / 构建任务可正常运行一小时。
const TIMEOUT_MS = 60 * 60 * 1000
const MAX_RESULT_CHARS = 256 * 1024
const pending = new Map()

export function requestTerminalDispatch({ sessionId, hostId, command, explanation, toolCallId, emit, signal }) {
  const requestId = randomUUID()

  return new Promise((resolve) => {
    const settle = (result) => {
      const entry = pending.get(requestId)
      if (!entry) return
      clearTimeout(entry.timer)
      pending.delete(requestId)
      if (signal && entry.onAbort) signal.removeEventListener('abort', entry.onAbort)
      resolve(result)
    }

    // 终端命令已经通过另一个 socket 写进 PTY。这里不能只结束 agent
    // 的等待，否则 UI 虽显示“已停止”，远端进程仍会继续跑。
    const cancel = (reason) => {
      emit({ type: 'terminal_command_cancel', requestId, toolCallId, reason })
      settle({ ok: false, error: reason })
    }

    const timer = setTimeout(() => {
      emit({ type: 'terminal_command_timeout', requestId, toolCallId })
      cancel('终端命令等待超时（60 分钟），已请求中断远端命令')
    }, TIMEOUT_MS)
    const onAbort = () => cancel('对话已停止，已请求中断远端命令')

    pending.set(requestId, { sessionId, toolCallId, emit, timer, onAbort, settle })
    if (signal) {
      if (signal.aborted) return onAbort()
      signal.addEventListener('abort', onAbort, { once: true })
    }

    emit({ type: 'terminal_command_request', requestId, hostId, command, explanation })
  })
}

export function resolveTerminalDispatch(requestId, payload = {}) {
  const entry = pending.get(requestId)
  if (!entry) return { ok: false, error: '终端命令请求已失效' }
  entry.settle({
    ok: Boolean(payload.ok),
    error: payload.error,
    output: typeof payload.output === 'string' ? payload.output.slice(-MAX_RESULT_CHARS) : '',
    capturedAt: Number.isFinite(payload.capturedAt) ? payload.capturedAt : undefined,
    durationMs: Number.isFinite(payload.durationMs) ? payload.durationMs : undefined,
    exitCode: Number.isFinite(payload.exitCode) ? payload.exitCode : null
  })
  return { ok: true }
}

export function reportTerminalDispatchProgress(requestId, payload = {}) {
  const entry = pending.get(requestId)
  if (!entry) return { ok: false, error: '终端命令请求已失效' }
  entry.emit({
    type: 'terminal_command_progress',
    requestId,
    toolCallId: entry.toolCallId,
    output: typeof payload.output === 'string' ? payload.output.slice(-6 * 1024) : '',
    capturedAt: Number.isFinite(payload.capturedAt) ? payload.capturedAt : undefined,
    durationMs: Number.isFinite(payload.durationMs) ? payload.durationMs : undefined
  })
  return { ok: true }
}

export function clearTerminalDispatchBySession(sessionId) {
  for (const [requestId, entry] of pending.entries()) {
    if (entry.sessionId !== sessionId) continue
    entry.emit({
      type: 'terminal_command_cancel',
      requestId,
      toolCallId: entry.toolCallId,
      reason: '会话已结束，已请求中断远端命令'
    })
    entry.settle({ ok: false, error: '会话已结束，已请求中断远端命令' })
  }
}
