/**
 * Agent 运行时
 *
 * 消费 streamText 的 fullStream，把 AI SDK 的事件映射成 easynode 自己的
 * socket 事件协议。之所以不用 AI SDK 的 HTTP data stream，是因为这里需要
 * 双向通信：审批回传、中途停止、切换权限档位。
 *
 * 审批采用"在回调里 await"的方式而不是 SDK 的 'user-approval' 状态 ——
 * 后者要求客户端按 HTTP 往返的方式续跑，在 socket 架构下反而更绕。
 */

import { streamText, stepCountIs } from 'ai'
import { createHash } from 'node:crypto'
import { resolveModel } from './provider.js'
import { buildTools } from './tools/index.js'
import { getToolSpec, requiresPlus } from './tools/spec.js'
import { checkRestrictedToolAccess } from './tools/executors.js'
import { buildSystemPrompt } from './prompt.js'
import { classifyCommand, Risk, primaryReason } from './safety.js'
import { DEFAULT_PRESET, Effect, Mode, isEffectAllowed, needsApproval, resolveEffectivePolicy } from './policy.js'
import { requestApproval } from './approval.js'
import { compactMessages, isContextLengthError } from './compaction.js'
import { resolveHostAccess, buildAllowedHostIds } from './host-access.js'
import { loadForModel } from './session-store.js'
import { writeAudit, ACTION } from './audit.js'
import { HostListDB } from '../utils/db-class.js'
import { requestTerminalDispatch } from './terminal-dispatch.js'
import { getScriptById } from '../script-library.js'
import { classifyReadPath, stricterDataRisk } from './data-policy.js'
import { buildWriteFilePreview } from './write-preview.js'
import { resolveRemotePath } from './remote-path.js'
import { isSensitiveMutationPath } from './file-mutation-policy.js'

const hostListDB = new HostListDB().getInstance()

/**
 * 组装目标主机摘要。具体调用仍按目标主机自己的策略判定，多主机之间
 * 不再互相收紧工具范围。
 */
async function loadHostSummaries(hostIds, sessionMode) {
  const policy = resolveEffectivePolicy(sessionMode)
  if (!hostIds?.length) return { hosts: [], policy }

  const hosts = await hostListDB.findAsync({ _id: { $in: hostIds } })
  const summaries = hosts.map((host) => {
    const resolved = resolveEffectivePolicy(sessionMode, host.aiPolicy)
    return {
      hostId: host._id,
      name: host.name,
      host: host.host,
      port: host.port,
      username: host.username,
      enabled: resolved.enabled,
      mode: resolved.mode,
      maxEffect: resolved.maxEffect,
      clamped: resolved.clamped.mode || resolved.clamped.effect
    }
  })
  policy.clamped = {
    mode: summaries.some((item) => item.mode !== policy.mode),
    effect: summaries.some((item) => item.maxEffect === Effect.READ)
  }
  policy.enabled = summaries.some((item) => item.enabled)
  return { hosts: summaries, policy }
}

/**
 * 构造 toolApproval 回调
 *
 * 四段判定，顺序不能变：
 *   1. deny  —— 硬拦截，任何档位都不放行，也不询问用户
 *   2. 主机策略 —— 目标主机的操作上限
 *   3. Plus —— 写入/删除在审批前即时验权
 *   4. 审批 —— 自动放行或挂起等用户
 */
function createToolApproval(ctx) {
  return async ({ toolCall }) => {
    const spec = getToolSpec(toolCall.toolName)
    if (!spec) return 'not-applicable'

    const input = toolCall.input || {}
    let approvalInput = input
    let approvalPreview = null
    let dataRisk = null
    let approvedReadPath = null
    let hostPolicy = ctx.policy
    let hostName
    if (input.hostId) {
      try {
        const access = await resolveHostAccess(input.hostId, ctx)
        hostPolicy = access.policy
        hostName = access.host.name
      } catch (error) {
        return denyToolCall(ctx, toolCall, input, error.message, '主机策略')
      }
    }

    let verdict = null
    let effect = spec.effect
    let risk = Risk.NORMAL
    let reason = null
    let targets = []
    let sensitiveDisclosure = false
    let scriptHash = null

    if (toolCall.toolName === 'run_script') {
      const script = await getScriptById(input.scriptId)
      if (!script?.command) {
        return denyToolCall(ctx, toolCall, input, '脚本不存在或没有可执行内容，请先刷新脚本库后重试', '脚本库')
      }
      verdict = classifyCommand(script.command)
      effect = verdict.effect
      risk = verdict.risk
      reason = primaryReason(verdict)
      targets = verdict.targets
      sensitiveDisclosure = hasSensitiveRead(verdict)
      scriptHash = createHash('sha256').update(script.command).digest('hex')
      approvalInput = {
        ...input,
        scriptName: script.name,
        command: script.command
      }
      ctx.toolMeta[toolCall.toolCallId] = { scriptName: script.name }
    }

    if (toolCall.toolName === 'read_file') {
      const realPath = await resolveRemotePath(input.hostId, input.path)
      dataRisk = stricterDataRisk(classifyReadPath(input.path), classifyReadPath(realPath))
      approvedReadPath = realPath
      effect = Effect.READ
      risk = dataRisk.risk
      targets = [realPath]
      if (risk === Risk.HIGH) {
        reason = dataRisk
        sensitiveDisclosure = true
        approvalPreview = { type: 'read_file', path: input.path, realPath, sensitiveDisclosure: true }
      }
    }

    const isTerminalCommand = ctx.scope === 'terminal' && toolCall.toolName === 'terminal_command'
    if ((toolCall.toolName === 'exec_command' || isTerminalCommand) && input.command) {
      verdict = classifyCommand(
        input.cwd ? `cd ${ input.cwd } && ${ input.command }` : String(input.command)
      )
      effect = verdict.effect
      risk = verdict.risk
      reason = primaryReason(verdict)
      targets = verdict.targets
      sensitiveDisclosure = hasSensitiveRead(verdict)
    }

    ctx.toolMeta[toolCall.toolCallId] = {
      ...(ctx.toolMeta[toolCall.toolCallId] || {}),
      effect,
      risk,
      targets,
      riskReason: reason?.reason,
      riskCategory: reason?.category,
      sensitiveDisclosure: sensitiveDisclosure || undefined
    }

    if (risk === Risk.DENY) {
      writeAudit({
        action: ACTION.DENIED,
        sessionId: ctx.sessionId,
        userId: ctx.userId,
        hostId: input.hostId,
        hostName,
        tool: toolCall.toolName,
        command: input.command || approvalInput.command,
        risk,
        reason: reason?.reason
      })
      ctx.toolMeta[toolCall.toolCallId].denied = true
      ctx.emit({ type: 'tool_denied', toolCallId: toolCall.toolCallId, tool: toolCall.toolName,
        reason: reason?.reason, category: reason?.category, command: input.command || approvalInput.command,
        permanent: true })
      return {
        type: 'denied',
        reason: `该命令被安全策略永久拒绝：${ reason?.reason || '命中拒绝规则' }。不要改写或拆分绕过；可以把原始命令展示给用户，由用户自行决定是否在终端执行。`
      }
    }

    if (!isEffectAllowed(effect, hostPolicy.maxEffect)) {
      return denyToolCall(ctx, toolCall, input,
        `主机「${ hostName || input.hostId }」仅允许 AI 读取，不能执行${ effect === Effect.DELETE ? '删除' : '写入' }操作`,
        '主机策略')
    }

    // Plus 是工具执行权限，不是会话启动时的能力快照。写操作在审批前
    // 读取当前授权，避免让用户确认一个必然无法执行的操作。
    if (requiresPlus(spec, effect)) {
      const access = await checkRestrictedToolAccess(
        ctx,
        toolCall.toolName,
        effect,
        toolCall.toolCallId
      )
      if (!access.ok) {
        ctx.toolMeta[toolCall.toolCallId] = {
          ...ctx.toolMeta[toolCall.toolCallId],
          denied: true,
          riskCategory: 'Plus 权限',
          riskReason: access.error
        }
        return { type: 'denied', reason: access.error }
      }
    }

    // write_file 的远端预览会建立 SFTP 连接，必须放在 Plus 校验之后。
    if (toolCall.toolName === 'write_file') {
      try {
        approvalPreview = await buildWriteFilePreview(input.hostId, input)
        approvalInput = { ...input }
        delete approvalInput.content
        targets = [approvalPreview.realPath]
        if (isSensitiveMutationPath(approvalPreview.realPath)) {
          risk = Risk.HIGH
          reason = {
            level: Risk.HIGH,
            category: '敏感路径变更',
            reason: '目标位于系统配置、账号或业务数据路径，需要单次确认'
          }
        }
        ctx.toolMeta[toolCall.toolCallId] = {
          ...ctx.toolMeta[toolCall.toolCallId],
          effect,
          risk,
          targets,
          riskReason: reason?.reason,
          riskCategory: reason?.category
        }
      } catch (error) {
        return denyToolCall(ctx, toolCall, input, `无法准备文件写入：${ error.message }`, '文件写入')
      }
    }

    const shouldApprove = needsApproval({
      mode: hostPolicy.mode,
      effect,
      risk,
      hostOperation: Boolean(input.hostId)
    })

    if (!shouldApprove) {
      authorizePreparedCall(ctx, toolCall.toolCallId, {
        approvalPreview,
        approvedReadPath,
        sensitiveDisclosure,
        scriptHash
      })
      return 'not-applicable'
    }

    const result = await requestApproval({
      sessionId: ctx.sessionId,
      toolName: toolCall.toolName,
      toolCallId: toolCall.toolCallId,
      input: approvalInput,
      mode: hostPolicy.mode,
      effect,
      targets,
      riskLevel: risk,
      risk: reason,
      hostName: hostName || ctx.hosts.find((item) => item.hostId === input.hostId)?.name,
      preview: approvalPreview,
      sensitiveDisclosure,
      grantable: hostPolicy.mode === Mode.ASSIST && effect === Effect.WRITE
        && risk === Risk.NORMAL && !isTerminalCommand,
      emit: ctx.emit,
      signal: ctx.signal
    })

    ctx.toolMeta[toolCall.toolCallId] = {
      ...ctx.toolMeta[toolCall.toolCallId],
      approved: result.approved,
      approvalScope: result.scope,
      approvalCached: result.cached || undefined
    }

    if (result.approved) {
      authorizePreparedCall(ctx, toolCall.toolCallId, {
        approvalPreview,
        approvedReadPath,
        sensitiveDisclosure,
        scriptHash
      })
      return { type: 'approved' }
    }
    return { type: 'denied', reason: result.reason || '用户拒绝了该操作' }
  }
}

function hasSensitiveRead(verdict) {
  return verdict?.hits.some((hit) => (
    hit.id.endsWith('read-blocked-credentials') || hit.id.endsWith('read-credentials')
  )) || false
}

function authorizePreparedCall(ctx, toolCallId, prepared) {
  if (prepared.approvalPreview?.type === 'write_file') {
    ctx.authorizedWrites.set(toolCallId, prepared.approvalPreview.snapshotHash)
  }
  if (prepared.approvedReadPath) ctx.approvedReads.set(toolCallId, prepared.approvedReadPath)
  if (prepared.sensitiveDisclosure) ctx.sensitiveOutputs.add(toolCallId)
  if (prepared.scriptHash) ctx.authorizedScripts.set(toolCallId, prepared.scriptHash)
}

function denyToolCall(ctx, toolCall, input, reason, category) {
  ctx.toolMeta[toolCall.toolCallId] = {
    ...(ctx.toolMeta[toolCall.toolCallId] || {}),
    denied: true,
    riskReason: reason,
    riskCategory: category
  }
  ctx.emit({ type: 'tool_denied', toolCallId: toolCall.toolCallId, tool: toolCall.toolName,
    reason, category, command: input.command, permanent: false })
  return { type: 'denied', reason }
}

/**
 * 跑一个 turn。
 *
 * @param {object} params
 * @param {string} params.sessionId
 * @param {string} [params.userId]
 * @param {Array}  params.messages ModelMessage[]
 * @param {string} [params.modelId]
 * @param {string} [params.permission] 会话模式
 * @param {string[]} [params.hostIds] 目标主机
 * @param {AbortSignal} params.signal
 * @param {(event: object) => void} params.emit 推送事件给前端
 * @returns {Promise<{ finishReason: string, usage: object, text: string }>}
 */
export async function runTurn(params) {
  const { sessionId, userId, userMessage, signal, emit } = params

  const sessionMode = params.scope === 'terminal'
    ? (params.terminalPermission || DEFAULT_PRESET)
    : (params.permission || DEFAULT_PRESET)
  const { hosts, policy } = await loadHostSummaries(params.hostIds, sessionMode)

  if (params.scope === 'terminal' && hosts.length !== 1) {
    throw new Error('终端 AI 必须绑定一个有效的目标主机')
  }

  if (!policy.enabled) {
    throw new Error('目标主机已被禁止 AI 操作，请在主机设置中开启后重试')
  }

  const { model, modelId, contextLimit, maxSteps } = await resolveModel({ modelId: params.modelId })
  // 显式传入的优先，其次是 AI 配置里的，最后落到 compaction 的默认值
  const effectiveContextLimit = params.contextLimit || contextLimit

  // 工具调用的展示用信息（风险判定、审批结果、耗时），随会话一起落盘，
  // 刷新页面后卡片才能还原成"已批准 / 被拦截"而不是一片空白
  const toolMeta = {}

  const ctx = {
    sessionId,
    userId,
    policy,
    sessionMode,
    scope: params.scope || 'ops',
    terminalHostId: params.terminalHostId,
    terminalPermission: params.terminalPermission || DEFAULT_PRESET,
    allowedHostIds: buildAllowedHostIds(params.hostIds),
    hosts,
    toolMeta,
    authorizedWrites: new Map(),
    authorizedScripts: new Map(),
    approvedReads: new Map(),
    sensitiveOutputs: new Set(),
    signal,
    emit,
    requestTerminalDispatch: params.scope === 'terminal'
      ? async (input) => requestTerminalDispatch({
        sessionId,
        hostId: params.terminalHostId,
        command: input.command,
        explanation: input.explanation,
        toolCallId: input.toolCallId,
        emit,
        signal
      })
      : null,
    onToolEvent: (event) => {
      if (event.toolCallId) {
        toolMeta[event.toolCallId] = {
          ...toolMeta[event.toolCallId],
          tool: event.tool,
          durationMs: event.durationMs,
          failed: event.phase === 'error' || undefined
        }
      }
      emit({ type: 'tool_progress', ...event })
    }
  }

  const tools = buildTools(ctx)

  emit({
    type: 'turn_start',
    sessionId,
    modelId,
    policy: { mode: policy.mode, maxEffect: policy.maxEffect, preset: policy.preset },
    clamped: policy.clamped,
    availableTools: Object.keys(tools),
    scope: ctx.scope,
    terminalPermission: ctx.scope === 'terminal' ? ctx.terminalPermission : undefined
  })

  const system = buildSystemPrompt(ctx)

  // 历史读取放在这里而不是 socket 层：主动压缩需要模型实例，而模型是这里
  // 解析的。放到调用方会导致 resolveModel 被解析两次、两处配置还可能不一致。
  // 主动压缩的落库在 session-store 内部完成（只有那里有稳定的消息下标）。
  const history = await loadForModel(sessionId, {
    model,
    contextLimit: effectiveContextLimit,
    signal
  })

  if (history.repaired) {
    emit({ type: 'history_repaired', count: history.repaired })
  }
  if (history.compactedNow) {
    emitCompaction(emit, history.compactedNow)
  }

  // 应急压缩：撞上厂商的上下文上限后强制压一次重试。这条不落库，
  // 因为 token 估算不准是常态，没必要为一次意外改写会话。
  const turnMessage = params.terminalContext
    ? withTerminalContext(userMessage, params.terminalContext, hosts[0])
    : userMessage
  let working = [...history.messages, turnMessage]
  let attempt = 0
  for (;;) {
    try {
      return await streamOnce({ model, system, messages: working, tools, ctx, maxSteps, toolMeta, emit, signal })
    } catch (error) {
      const retryable = attempt === 0 && !signal?.aborted && isContextLengthError(error)
      if (!retryable) {
        // streamOnce 在已有输出时会自行上报，避免重复推送 error 事件
        if (!error.alreadyReported) {
          logger.error(`[ai-runtime] turn 执行失败: ${ error.message }`)
          emit({ type: 'error', message: error.message })
        }
        // 已经执行过工具的话，把这部分结果返回而不是抛出 ——
        // 调用方据此落盘，历史才不会缺一块
        if (error.partialResult) return { ...error.partialResult, error: error.message }
        throw error
      }

      attempt += 1
      logger.warn('[ai-runtime] 上下文超限，强制压缩后重试')
      const forced = await compactMessages({
        messages: working,
        model,
        contextLimit: effectiveContextLimit,
        force: true,
        keepRecentTurns: 1,
        signal
      })
      if (!forced.compacted) {
        // 已经压无可压，说明单轮内容本身就超限，如实报错
        emit({ type: 'error', message: `上下文超出模型限制，且已无可压缩的历史：${ error.message }` })
        throw error
      }
      working = forced.messages
      emitCompaction(emit, forced)
    }
  }
}

/**
 * 终端画面不作为模型记忆。真正可审计的命令输出由 terminal_command 的
 * tool result 进入会话历史；这里仅标记当前用户正在使用哪一个 Web 终端。
 */
function withTerminalContext(userMessage, terminalContext, host) {
  const output = String(terminalContext.output || '').trim()
  const capturedAt = terminalContext.capturedAt ? new Date(terminalContext.capturedAt).toLocaleString('zh-CN') : '刚刚'
  const text = [
    typeof userMessage.content === 'string' ? userMessage.content : '',
    '',
    `[当前 Web 终端：${ host?.name || terminalContext.hostName || '未知主机' }，连接状态正常，时间 ${ capturedAt }]`,
    output ? `[用户显式附带的终端文本]\n${ output }` : ''
  ].join('\n')
  return { ...userMessage, content: text }
}

function emitCompaction(emit, result) {
  emit({
    type: 'compacted',
    droppedCount: result.droppedCount,
    beforeTokens: result.beforeTokens,
    afterTokens: result.afterTokens,
    degraded: result.degraded || false,
    reason: result.reason
  })
}

/**
 * 跑一次流式请求并把事件映射出去。
 *
 * 抽成独立函数是为了让上下文超限重试能整体重跑一次，而不必在事件循环里
 * 判断"这次是不是重试"。
 */
async function streamOnce({ model, system, messages, tools, ctx, maxSteps, toolMeta, emit, signal }) {
  let accumulated = ''
  let produced = false
  let awaitingModelAfterTool = null

  const result = streamText({
    model,
    system,
    messages,
    tools,
    toolApproval: createToolApproval(ctx),
    stopWhen: stepCountIs(maxSteps),
    abortSignal: signal
  })

  // 只有真正推给用户的内容才算"已产出"。start / finish-step 这类
  // 控制片段不算，否则超限错误会因为收到过一个空片段而失去重试机会。
  const VISIBLE_PARTS = new Set(['text-delta', 'reasoning-delta', 'tool-call', 'tool-result', 'tool-error'])

  try {
    for await (const part of result.fullStream) {
      // finish-step 仅代表这一轮工具步骤收尾，随后 SDK 还会把工具结果
      // 回传给模型并等待下一轮输出；不能在这里结束“分析工具结果”状态。
      if (awaitingModelAfterTool && ['text-delta', 'reasoning-delta', 'tool-call'].includes(part.type)) {
        const durationMs = Date.now() - awaitingModelAfterTool.startedAt
        console.info('[ai-agent] 模型已处理工具结果', {
          sessionId: ctx.sessionId,
          toolCallId: awaitingModelAfterTool.toolCallId,
          durationMs,
          nextEvent: part.type
        })
        emit({ type: 'model_resumed', toolCallId: awaitingModelAfterTool.toolCallId, durationMs })
        awaitingModelAfterTool = null
      }

      // 一旦有内容产出就不能再重试，否则前端会看到两遍
      if (VISIBLE_PARTS.has(part.type)) produced = true
      switch (part.type) {
        case 'text-delta':
          accumulated += part.text
          emit({ type: 'text_delta', text: part.text })
          break

        case 'reasoning-delta':
          emit({ type: 'reasoning_delta', text: part.text })
          break

        case 'tool-call':
          emit({
            type: 'tool_call',
            toolCallId: part.toolCallId,
            tool: part.toolName,
            input: part.input
          })
          break

        case 'tool-result':
          emit({
            type: 'tool_result',
            toolCallId: part.toolCallId,
            tool: part.toolName,
            output: part.output
          })
          awaitingModelAfterTool = { toolCallId: part.toolCallId, startedAt: Date.now() }
          emit({ type: 'awaiting_model', toolCallId: part.toolCallId })
          break

        case 'tool-error':
          emit({
            type: 'tool_result',
            toolCallId: part.toolCallId,
            tool: part.toolName,
            error: String(part.error?.message || part.error)
          })
          awaitingModelAfterTool = { toolCallId: part.toolCallId, startedAt: Date.now() }
          emit({ type: 'awaiting_model', toolCallId: part.toolCallId })
          break

        case 'finish-step':
          emit({ type: 'step_finish', usage: part.usage, finishReason: part.finishReason })
          break

        case 'error':
          // 流内的 error 片段不等于整轮失败（后续 step 可能仍会产出），
          // 用独立类型上报，避免前端据此把工具卡片全标成失败
          emit({ type: 'stream_error', message: String(part.error?.message || part.error) })
          break

        default:
          // 其余事件（start / finish / source / file 等）暂不透传
          break
      }
    }

    const [finishReason, usage, responseMessages] = await Promise.all([
      result.finishReason,
      result.totalUsage,
      result.responseMessages
    ])

    emit({ type: 'finish', finishReason, usage, text: accumulated })
    return { finishReason, usage, text: accumulated, responseMessages, toolMeta }
  } catch (error) {
    // 中断或失败时都要把已产生的消息交出去。丢掉的话，历史里会留下
    // "有 tool-call 没有 tool-result"的残缺记录，更糟的是模型已经真的
    // 在主机上执行过命令，却没有任何记录
    const partial = await collectPartialMessages(result)

    if (signal?.aborted) {
      emit({ type: 'aborted', text: accumulated })
      return { finishReason: 'abort', usage: null, text: accumulated, responseMessages: partial, toolMeta }
    }
    // 还没产出任何内容时把错误原样抛出，交给上层判断能否压缩重试；
    // 已经产出过就不能重试（会重复输出），把部分结果带上一起抛，
    // 让 socket 层仍然能把这一轮落盘
    if (!produced) throw error

    logger.error(`[ai-runtime] turn 执行失败: ${ error.message }`)
    emit({ type: 'error', message: error.message })
    throw Object.assign(error, {
      alreadyReported: true,
      partialResult: { finishReason: 'error', usage: null, text: accumulated, responseMessages: partial, toolMeta }
    })
  }
}

/** 尽力取出流已产生的消息，取不到就返回空数组，不能因此再抛错 */
async function collectPartialMessages(result) {
  try {
    return await result.responseMessages
  } catch {
    return []
  }
}
